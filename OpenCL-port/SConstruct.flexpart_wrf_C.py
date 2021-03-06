#INCF	= incl*

# -m64 :: a 64-bit environment allows access to memory and files in excess of 2GB
# frecord-marker=4 ::  use 4-byte record markers by default for 
# unformatted files to be compatible with g77 and most other compilers
FFLAGS  = ['-O3', '-m64', '-fconvert=little-endian', '-frecord-marker=4']
#-I$(NETCDF)/include

#
csources=['windalign.c']
fsources = ['assignland.f', 'writeheader.f', 'calcpar.f', 'part0.f', 'caldate.f', 'partdep.f', 'coordtrafo.f', 'psih.f', 'sincosd.f', 'raerod.f',
        'drydepokernel.f', 'random.f', 'erf.f', 'readavailable.f', 'ew.f', 'readcommand.f', 'advance.f', 'readdepo.f', 'releaseparticles.f', 'psim.f',
        'flexpart_wrf.f', 'readlanduse.f', 'getfields.f', 'init_domainfill.f', 'interpol_wind.f', 'readoutgrid.f', 'interpol_all.f', 'readpaths.f', 'getrb.f',
        'readreceptors.f', 'getrc.f', 'readreleases.f', 'getvdep.f', 'readspecies.f', 'interpol_misslev.f', 'readwind.f', 'conccalc.f', 'richardson.f',
        'concoutput.f', 'scalev.f', 'pbl_profile.f', 'juldate.f', 'timemanager.f', 'interpol_vdep.f', 'interpol_rain.f', 'verttransform.f', 'partoutput.f',
        'hanna.f', 'wetdepokernel.f', 'mean.f', 'wetdepo.f', 'hanna_short.f', 'obukhov.f', 'gridcheck.f', 'hanna1.f', 'initialize.f',
        'cmapf1.0.f', 'gridcheck_nests.f', 'readwind_nests.f', 'calcpar_nests.f', 'verttransform_nests.f', 'interpol_all_nests.f', 'interpol_wind_nests.f',
        'interpol_misslev_nests.f', 'interpol_vdep_nests.f', 'interpol_rain_nests.f', 'readageclasses.f', 'readpartpositions.f', 'calcfluxes.f', 'fluxoutput.f',
        'qvsat.f', 'skplin.f', 'convmix.f', 'calcmatrix.f', 'convect43c.f', 'redist.f', 'sort2.f', 'distance.f', 'centerofmass.f', 'plumetraj.f',
        'openouttraj.f', 'calcpv.f', 'calcpv_nests.f', 'distance2.f', 'clustering.f', 'interpol_wind_short.f', 'interpol_wind_short_nests.f', 'shift_field_0.f',
        'shift_field.f', 'outgrid_init.f', 'openreceptors.f', 'boundcond_domainfill.f', 'partoutput_short.f', 'readoutgrid_nest.f', 'outgrid_init_nest.f',
        'writeheader_nest.f', 'concoutput_nest.f', 'wetdepokernel_nest.f', 'drydepokernel_nest.f', 'read_ncwrfout.f', 'map_proj_wrf.f', 'map_proj_wrf_subaa.f']


#envCxx=Environment(CXX='g++');
#envCxx.Library('testCxx',cxxsources)
envC=Environment(CC='gcc',CPPPATH=['/Users/wim/SoC_Research/F2C-ACC/include/']);
envC.Library('wrfc',csources)

envF=Environment(FORTRAN='/opt/local/bin/gfortran-mp-4.6',FORTRANFLAGS=FFLAGS,FORTRANPATH=['.','/opt/local/include'])
envF.Program('flexpart_wrf_c',fsources,LIBS=['netcdff','wrfc','m'],LIBPATH=['.','/opt/local/lib'])		

