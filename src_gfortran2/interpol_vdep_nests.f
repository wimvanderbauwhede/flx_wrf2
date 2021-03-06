      subroutine interpol_vdep_nests(level,vdepo)
C                                      i     o
*****************************************************************************
*                                                                           *
*  Interpolation of the deposition velocity on 2-d model layer.             *
*  In horizontal direction bilinear interpolation interpolation is used.    *
*  Temporally a linear interpolation is used.                               *
*                                                                           *
*  1 first time                                                             *
*  2 second time                                                            *
*                                                                           *
*                                                                           *
*     Author: A. Stohl                                                      *
*                                                                           *
*     30 May 1994                                                           *
*                                                                           *
*****************************************************************************
*                                                                           *
* Variables:                                                                *
*                                                                           *
* level                number of species for which interpolation is done    *
*                                                                           *
*****************************************************************************


      include 'includepar'
      include 'includecom'
      include 'includeinterpol'

      integer level,indexh,m
      real y(2),vdepo
     
C a) Bilinear horizontal interpolation

      do 10 m=1,2
        indexh=memind(m)

10      y(m)=p1*vdepn(ix ,jy ,level,indexh,ngrid)
     +      +p2*vdepn(ixp,jy ,level,indexh,ngrid)
     +      +p3*vdepn(ix ,jyp,level,indexh,ngrid)
     +      +p4*vdepn(ixp,jyp,level,indexh,ngrid)


C b) Temporal interpolation

      vdepo=(y(1)*dt2+y(2)*dt1)*dtt

      depoindicator(level)=.false.


      end
