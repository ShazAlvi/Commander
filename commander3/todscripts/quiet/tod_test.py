import numpy as np
import matplotlib.pyplot as plt
import h5py


d = h5py.File('/mn/stornext/u3/hke/quiet_data/level3/Q/ces/patch_gc/patch_gc_2571.hdf', 'r')


t = d['time'][...]
tod = d['tod'][...] # 76 x N_TOD
# There are 19 horns (modules)
# Each module has 4 radiometers (diodes), 1 and 4 have most of the signal
point = d['point']
phi, theta, psi = point[:,:,0], point[:,:,1], point[:,:,2]




plt.show()
