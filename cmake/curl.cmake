# Project: Curl 
# Project link: https://github.com/curl/curl
# Curl is a command-line tool for transferring data specified with URL syntax
# Required by: CFitsio
# Author: Maksym Brilenkov


# looking for curl in the system and download it if it is not present
find_package(CURL)
if(NOT CURL_FOUND)
	message(STATUS "Haven't found curl on the system. Will download and compile it from source:
	https://github.com/curl/curl")
	ExternalProject_Add(${project}
		URL "${${project}_url}"
		PREFIX "${CMAKE_DOWNLOAD_DIRECTORY}/${project}"
		DOWNLOAD_DIR "${CMAKE_DOWNLOAD_DIRECTORY}" #"${download_dir}"
		BINARY_DIR "${CMAKE_DOWNLOAD_DIRECTORY}/${project}/src/${project}"
		INSTALL_DIR "${CMAKE_INSTALL_OUTPUT_DIRECTORY}" #"${out_install_dir}"
		#PATCH_COMMAND ./buildconf
		CONFIGURE_COMMAND "${${${project}_configure}_command}"
		COMMAND ${CMAKE_COMMAND} -E env FC=${CMAKE_Fortran_COMPILER} CXX=${CMAKE_CXX_COMPILER} CC=${CMAKE_C_COMPILER} MPCC=${CMAKE_C_COMPILER} MPFC=${CMAKE_Fortran_COMPILER} MPCXX=${CMAKE_CXX_COMPILER} ./configure --prefix=<INSTALL_DIR>
		#LOG_DOWNLOAD ON
		#LOG_UPDATE ON
		#LOG_CONFIGURE ON
		#LOG_BUILD ON
		#LOG_TEST ON
		#LOG_INSTALL ON
		)
	# getting curl directories
	ExternalProject_Get_Property(${project} source_dir)
    ExternalProject_Get_Property(${project} install_dir)
	# specifying curl libraries and binaries
	set(CURL_SOURCE_DIR ${source_dir})
    set(CURL_BINARY_DIR ${install_dir}/bin)
	set(CURL_INCLUDE_DIR ${install_dir}/include)#/${project})
    set(CURL_LIBRARIES ${install_dir}/lib/${CMAKE_STATIC_LIBRARY_PREFIX}${project}${CMAKE_STATIC_LIBRARY_SUFFIX})
	# including curl into a project
	#include_directories(${CURL_SOURCE_DIR})
	include_directories(${CURL_BINARY_DIR})
	include_directories(${CURL_INCLUDE_DIR})
	message(STATUS "Curl INCLUDE DIR will be ${CURL_INCLUDE_DIR}")
	message(STATUS "Curl BINARY DIR will be ${CURL_BINARY_DIR}")
	message(STATUS "Curl SOURCE DIR will be ${CURL_SOURCE_DIR}")
	message(STATUS "Curl LIBRARIES will be ${CURL_LIBRARIES}")

	#LIST(APPEND CMAKE_PROGRAM_PATH  "${CURL_BINARY_DIR}")
	#set(${project}_bin ${install_dir}/bin)
	# adding curl as an external library
	#add_library(${project}_lib STATIC IMPORTED GLOBAL)
	# asking cmake to identify its name for us
	#set(${${project}_lib}_name ${CMAKE_STATIC_LIBRARY_PREFIX}${project}${CMAKE_STATIC_LIBRARY_SUFFIX})
	# Specifying the directory
	#set_target_properties(${${project}_lib} PROPERTIES IMPORTED_LOCATION "${out_install_dir}/lib/${${${project}_lib}_name}")
	#add_custom_target(${project}_bin WORKING_DIRECTORY ${out_install_dir}/bin)
	# exporting curl so, cfitsio will be able to find it
	#execute_process(COMMAND export PATH=$PATH:/mn/stornext/u3/maksymb/cmake_tests/CommanderSuperbuild/build/install/lib)
	# setting an environment variable for cfitsio to find curl library
	set(ENV{PATH} 
		#$ENV{PATH}:${out_install_dir}/include/:${out_lib_dir}/:${out_bin_dir}/curl
		$ENV{PATH}:${CMAKE_RUNTIME_OUTPUT_DIRECTORY}
		)
	message(STATUS "ENV PATH: " $ENV{PATH})
else()
	add_custom_target(${project} ALL "")
	include_directories(${CURL_INCLUDE_DIR})
	include_directories(${CURL_BINARY_DIR})
	message(STATUS "Curl INCLUDE DIR is ${CURL_INCLUDE_DIR}")
	message(STATUS "Curl BINARY DIR is ${CURL_BINARY_DIR}")
	message(STATUS "Curl SOURCE DIR is ${CURL_SOURCE_DIR}")
	message(STATUS "Curl LIBRARIES are ${CURL_LIBRARIES}")
	# setting an environment variable for cfitsio to find curl library
	set(ENV{PATH} 
		#$ENV{PATH}:${out_install_dir}/include/:${out_lib_dir}/:${out_bin_dir}/curl
		$ENV{PATH}
		)
	message(STATUS "ENV PATH: " $ENV{PATH})
	# Healpix complains about curl library - it needs to be in the same location as cfitsio
	add_custom_command(
		TARGET ${project} PRE_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
                ${CURL_LIBRARIES} 
				${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/${CMAKE_SHARED_LIBRARY_PREFIX}curl${CMAKE_SHARED_LIBRARY_SUFFIX}
				)
endif()

