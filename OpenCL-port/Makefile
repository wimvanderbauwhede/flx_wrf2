SHELL = /bin/bash
MAIN = flexpart_wrf
INCF	= incl*
#NETCDF = /Users/wim/SoC_Research/FLEXPART/flx_wrf2/src_gfortran2
NETCDF = /opt/local
# /mnt/disk1/work/saji/GNU/


# -m64 :: a 64-bit environment allows access to memory and files in excess of 2GB
# frecord-marker=4 ::  use 4-byte record markers by default for 
# unformatted files to be compatible with g77 and most other compilers
#FC      = gfortran-4.6
FC      = gfortran-mp-4.3
FFLAGS  = -O3 -m64 -fconvert=little-endian -frecord-marker=4 -I$(NETCDF)/include
LDFLAGS =  -L$(NETCDF)/lib -lnetcdff -lm

#
OBJECTS = assignland.o  writeheader.o \
calcpar.o               part0.o \
caldate.o               partdep.o \
coordtrafo.o            psih.o \
sincosd.o               raerod.o \
drydepokernel.o         random.o \
erf.o                   readavailable.o \
ew.o                    readcommand.o \
advance.o               readdepo.o \
releaseparticles.o      psim.o     \
flexpart_wrf.o          readlanduse.o \
getfields.o             init_domainfill.o\
interpol_wind.o         readoutgrid.o \
interpol_all.o          readpaths.o \
getrb.o                 readreceptors.o \
getrc.o                 readreleases.o \
getvdep.o               readspecies.o \
interpol_misslev.o      readwind.o \
conccalc.o              richardson.o \
concoutput.o            scalev.o \
pbl_profile.o           \
juldate.o               timemanager.o \
interpol_vdep.o         interpol_rain.o \
verttransform.o         partoutput.o \
hanna.o                 wetdepokernel.o \
mean.o                  wetdepo.o \
hanna_short.o           windalign.o \
obukhov.o               gridcheck.o \
hanna1.o                initialize.o \
cmapf1.0.o              gridcheck_nests.o \
readwind_nests.o        calcpar_nests.o \
verttransform_nests.o   interpol_all_nests.o \
interpol_wind_nests.o   interpol_misslev_nests.o \
interpol_vdep_nests.o   interpol_rain_nests.o \
readageclasses.o        readpartpositions.o \
calcfluxes.o            fluxoutput.o \
qvsat.o                 skplin.o \
convmix.o               calcmatrix.o \
convect43c.o               redist.o \
sort2.o                 distance.o \
centerofmass.o          plumetraj.o \
openouttraj.o           calcpv.o \
calcpv_nests.o          distance2.o \
clustering.o            interpol_wind_short.o \
interpol_wind_short_nests.o shift_field_0.o \
shift_field.o           outgrid_init.o \
openreceptors.o         boundcond_domainfill.o\
partoutput_short.o      readoutgrid_nest.o \
outgrid_init_nest.o     writeheader_nest.o \
concoutput_nest.o       wetdepokernel_nest.o \
drydepokernel_nest.o 	\
read_ncwrfout.o         map_proj_wrf.o \
map_proj_wrf_subaa.o


$(MAIN): $(OBJECTS)
	$(FC)  -o $(MAIN)  $(FFLAGS) $(OBJECTS) $(LDFLAGS)
clean:
	rm *.o
$(OBJECTS): $(INCF)

