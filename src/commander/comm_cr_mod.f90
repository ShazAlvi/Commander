module comm_cr_mod
  use comm_comp_mod
  use comm_data_mod
  use comm_param_mod
  use comm_diffuse_comp_mod
  use comm_template_comp_mod
  use rngmod
  use comm_cr_utils
  implicit none

  private
  public solve_cr_eqn_by_CG, cr_amp2x, cr_x2amp, cr_computeRHS, cr_matmulA, cr_invM

  interface cr_amp2x
     module procedure cr_amp2x_full
  end interface cr_amp2x

  interface cr_x2amp
     module procedure cr_x2amp_full
  end interface cr_x2amp

contains

  recursive subroutine solve_cr_eqn_by_CG(cpar, A, invM, x, b, stat, P)
    implicit none

    type(comm_params),                intent(in)    :: cpar
    real(dp),          dimension(1:), intent(out)   :: x
    real(dp),          dimension(1:), intent(in)    :: b
    integer(i4b),                     intent(out)   :: stat
    class(precondDiff),               intent(inout) :: P

    interface
       recursive function A(x, Nscale)
         import dp
         implicit none
         real(dp), dimension(:),       intent(in)           :: x
         real(dp), dimension(size(x))                       :: A
         real(dp),                     intent(in), optional :: Nscale
       end function A

       recursive function invM(x, P)
         import precondDiff, dp
         implicit none
         real(dp),              dimension(:), intent(in) :: x
         class(precondDiff),                  intent(in) :: P
         real(dp), allocatable, dimension(:)             :: invM
       end function invM
    end interface

    integer(i4b) :: i, j, k, l, m, n, maxiter, root, ierr
    real(dp)     :: eps, tol, delta0, delta_new, delta_old, alpha, beta, t1, t2
    real(dp), allocatable, dimension(:)   :: Ax, r, d, q, temp_vec, s
    real(dp), allocatable, dimension(:,:) :: alm
    class(comm_comp),   pointer :: c

    root    = 0
    maxiter = cpar%cg_maxiter
    eps     = cpar%cg_tol
    n       = size(x)

    ! Allocate temporary data vectors
    allocate(Ax(n), r(n), d(n), q(n), s(n))

    ! Update preconditioner
    call P%update
    
    ! Initialize the CG search
    x  = 0.d0
    r  = b ! - A(x)   ! x is zero
    d  = invM(r, P)

    delta_new = mpi_dot_product(cpar%comm_chain,r,d)
    delta0    = delta_new
    do i = 1, maxiter
       call wall_time(t1)
       
       if (delta_new < eps * delta0) exit

       q     = A(d)
       alpha = delta_new / mpi_dot_product(cpar%comm_chain, d, q)
       x     = x + alpha * d

       ! Restart every 50th iteration to suppress numerical errors
       if (mod(i,50) == 0) then
          r = b - A(x)
       else
          r = r - alpha*q
       end if

       s         = invM(r, P)
       delta_old = delta_new 
       delta_new = mpi_dot_product(cpar%comm_chain, r, s)
       beta      = delta_new / delta_old
       d         = s + beta * d

       call wall_time(t2)
       if (cpar%myid == root .and. cpar%verbosity > 2) then
          write(*,fmt='(a,i5,a,e13.5,a,e13.5,a,f6.2)') 'CG iter. ', i, ' -- res = ', &
               & real(delta_new,sp), ', tol = ', real(eps * delta0,sp), &
               & ', wall time = ', real(t2-t1,sp)
       end if

    end do

    ! Multiply with sqrt(S)
    c       => compList
    do while (associated(c))
       select type (c)
       class is (comm_diffuse_comp)
          if (trim(c%cltype) == 'none') exit
          allocate(alm(0:c%x%info%nalm-1,c%x%info%nmaps))
          call cr_extract_comp(c%id, x, alm)
          call c%Cl%sqrtS(alm=alm) ! Multiply with sqrt(Cl)
          call cr_insert_comp(c%id, .false., alm, x)
          deallocate(alm)
       end select
       c => c%next()
    end do
    
    if (i >= maxiter) then
       write(*,*) 'ERROR: Convergence in CG search not reached within maximum'
       write(*,*) '       number of iterations = ', maxiter
       stat = stat + 1
    else
       if (cpar%myid == root .and. cpar%verbosity > 1) then
          write(*,fmt='(a,i5,a,e13.5,a,e13.5,a,f8.2)') 'Final CG iter ', i-1, ' -- res = ', &
               & real(delta_new,sp), ', tol = ', real(eps * delta0,sp)
       end if
    end if

    deallocate(Ax, r, d, q, s)
    
  end subroutine solve_cr_eqn_by_CG

  function cr_amp2x_full()
    implicit none

    real(dp), allocatable, dimension(:) :: cr_amp2x_full

    integer(i4b) :: i, ind
    class(comm_comp), pointer :: c

    ! Stack parameters linearly
    allocate(cr_amp2x_full(ncr))
    ind = 1
    c   => compList
    do while (associated(c))
       select type (c)
       class is (comm_diffuse_comp)
          do i = 1, c%x%info%nmaps
             cr_amp2x_full(ind:ind+c%x%info%nalm-1) = c%x%alm(:,i)
             ind = ind + c%x%info%nalm
          end do
       end select
       c => c%next()
    end do

  end function cr_amp2x_full

  subroutine cr_x2amp_full(x)
    implicit none

    real(dp), dimension(:), intent(in) :: x

    integer(i4b) :: i, ind
    class(comm_comp), pointer :: c

    ind = 1
    c   => compList
    do while (associated(c))
       select type (c)
       class is (comm_diffuse_comp)
          do i = 1, c%x%info%nmaps
             c%x%alm(:,i) = x(ind:ind+c%x%info%nalm-1)
             ind = ind + c%x%info%nalm
          end do
       end select
       c => c%next()
    end do
    
  end subroutine cr_x2amp_full

  ! ---------------------------
  ! Definition of linear system
  ! ---------------------------

  subroutine cr_computeRHS(handle, rhs)
    implicit none

    type(planck_rng),                            intent(inout)          :: handle
    real(dp),         allocatable, dimension(:), intent(out)            :: rhs

    integer(i4b) :: i, j, l, m, k, n, ierr
    class(comm_map),     pointer                 :: map, Tm
    class(comm_comp),    pointer                 :: c
    class(comm_mapinfo), pointer                 :: info
    real(dp),        allocatable, dimension(:,:) :: eta

    call rand_init(handle, 10)
    
    ! Initialize output vector
    allocate(rhs(ncr))
    rhs = 0.d0

    ! Add channel dependent terms
    do i = 1, numband

       ! Set up Wiener filter term
       map => comm_map(data(i)%map)
       call data(i)%N%sqrtInvN(map)

       ! Add channel-dependent white noise fluctuation
       do k = 1, map%info%nmaps
          do j = 0, map%info%np-1
             map%map(j,k) = map%map(j,k) + rand_gauss(handle)
          end do
       end do

       ! Multiply with sqrt(invN)
       call data(i)%N%sqrtInvN(map)

       ! Convolve with transpose beam
       call data(i)%B%conv(alm_in=.false., alm_out=.false., trans=.true., map=map)
       
       ! Multiply with (transpose and component specific) mixing matrix, and
       ! insert into correct segment
       c => compList
       do while (associated(c))
          select type (c)
          class is (comm_diffuse_comp)
             info  => comm_mapinfo(data(i)%info%comm, data(i)%info%nside, c%lmax_amp, &
                  & c%nmaps, data(i)%info%pol)
             Tm     => comm_map(info)
             Tm%map = map%map
             Tm%map = c%F(i)%p%map * map%map
             call Tm%Yt
             call c%Cl%sqrtS(map=Tm) ! Multiply with sqrt(Cl)
             call cr_insert_comp(c%id, .true., Tm%alm, rhs)
             deallocate(Tm)
          end select
          c => c%next()
       end do

       deallocate(map)
    end do

    ! Add prior dependent terms
    c => compList
    do while (associated(c))
       select type (c)
       class is (comm_diffuse_comp)
          if (trim(c%cltype) == 'none') exit
          n = ind_comp(c%id,2)
          allocate(eta(c%x%info%nalm,c%x%info%nmaps))
          do j = 1, c%x%info%nmaps
             do i = 1, c%x%info%nalm
                eta(i,j) = rand_gauss(handle)
             end do
          end do
          call cr_insert_comp(c%id, .true., eta, rhs)
          deallocate(eta)
       end select
       c => c%next()
    end do
    nullify(c)

  end subroutine cr_computeRHS

  recursive function cr_matmulA(x, Nscale)
    implicit none

    real(dp), dimension(1:),     intent(in)             :: x
    real(dp),                    intent(in),   optional :: Nscale
    real(dp), dimension(size(x))                        :: cr_matmulA

    real(dp)                  :: t1, t2
    integer(i4b)              :: i, j
    class(comm_map),  pointer :: map
    class(comm_comp), pointer :: c
    real(dp),        allocatable, dimension(:)   :: y, sqrtS_x
    real(dp),        allocatable, dimension(:,:) :: alm, m

    ! Initialize output array
    allocate(y(ncr), sqrtS_x(ncr))
    y = 0.d0

    ! Multiply with sqrt(S)
    call wall_time(t1)
    sqrtS_x = x
    c       => compList
    do while (associated(c))
       select type (c)
       class is (comm_diffuse_comp)
          if (trim(c%cltype) == 'none') exit
          allocate(alm(0:c%x%info%nalm-1,c%x%info%nmaps))
          call cr_extract_comp(c%id, sqrtS_x, alm)
          call c%Cl%sqrtS(alm=alm) ! Multiply with sqrt(Cl)
          call cr_insert_comp(c%id, .false., alm, sqrtS_x)
          deallocate(alm)
       end select
       c => c%next()
    end do
    call wall_time(t2)
!    write(*,*) 'a', t2-t1

    
    ! Add frequency dependent terms
    do i = 1, numband

       ! Compute component-summed map, ie., column-wise matrix elements
       call wall_time(t1)
       map => comm_map(data(i)%info)
       c   => compList
       do while (associated(c))
          select type (c)
          class is (comm_diffuse_comp)
             call cr_extract_comp(c%id, sqrtS_x, alm)
             m = c%getBand(i, amp_in=alm)
             map%map = map%map + m
             deallocate(alm, m)
          end select
          c => c%next()
       end do
       call wall_time(t2)
!       write(*,*) 'b', t2-t1

       ! Multiply with invN
       call wall_time(t1)
       call data(i)%N%InvN(map, Nscale)
       call wall_time(t2)
!       write(*,*) 'c', t2-t1

       ! Project summed map into components, ie., row-wise matrix elements
       call wall_time(t1)
       c   => compList
       do while (associated(c))
          select type (c)
          class is (comm_diffuse_comp)
             alm = c%projectBand(i, map)
             call cr_insert_comp(c%id, .true., alm, y)
             deallocate(alm)
          end select
          c => c%next()
       end do
       call wall_time(t2)
!       write(*,*) 'd', t2-t1

       deallocate(map)
       
    end do

    ! Add prior term and multiply with sqrt(S) for relevant components
    call wall_time(t1)
    c   => compList
    do while (associated(c))
       select type (c)
       class is (comm_diffuse_comp)
          if (trim(c%cltype) == 'none') exit
          allocate(alm(0:c%x%info%nalm-1,c%x%info%nmaps))
          ! Multiply with sqrt(Cl)
          call cr_extract_comp(c%id, y, alm)
          call c%Cl%sqrtS(alm=alm)
          call cr_insert_comp(c%id, .false., alm, y)
          ! Add (unity) prior term
          call cr_extract_comp(c%id, x, alm)
          call cr_insert_comp(c%id, .true., alm, y)
          deallocate(alm)
       end select
       c => c%next()
    end do
    nullify(c)
    call wall_time(t2)
!    write(*,*) 'e', t2-t1

    ! Return result and clean up
    call wall_time(t1)
    cr_matmulA = y
    deallocate(y, sqrtS_x)
    call wall_time(t2)
!    write(*,*) 'f', t2-t1
    
  end function cr_matmulA

  recursive function cr_invM(x, P)
    implicit none
    real(dp),              dimension(:), intent(in) :: x
    class(precondDiff),                  intent(in) :: P
    real(dp), allocatable, dimension(:)             :: cr_invM

    integer(i4b) :: ierr
    real(dp), allocatable, dimension(:,:) :: alm
    class(comm_comp), pointer :: c

    if (.not. allocated(cr_invM)) allocate(cr_invM(size(x)))
    cr_invM = x
    
!!$    c => compList
!!$    do while (associated(c))
!!$       select type (c)
!!$       class is (comm_diffuse_comp)
!!$          allocate(alm(c%x%info%nalm,c%x%info%nmaps))
!!$          call cr_extract_comp(c%id, x, alm)          
!!$          call c%invM(Nscale, alm)
!!$          call cr_insert_comp(c%id, .false., alm, cr_invM)
!!$          deallocate(alm)
!!$       end select
!!$       c => c%next()
!!$    end do

    ! Jointly precondition diffuse components
    call precond_diff_comps(P, cr_invM)
    
  end function cr_invM

  
end module comm_cr_mod