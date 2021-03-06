      function psih (z,L)
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * 
*                                                                             *
*     Calculation of the stability correction term                            *
*                                                                             *
*     AUTHOR: Matthias Langer, adapted by Andreas Stohl (6 August 1993)       *
*             Update: G. Wotawa, 11 October 1994                              *
*                                                                             *
*     Literature:                                                             *
*     [1] C.A.Paulson (1970), A Mathematical Representation of Wind Speed     *
*           and Temperature Profiles in the Unstable Atmospheric Surface      *
*           Layer. J.Appl.Met.,Vol.9.(1970), pp.857-861.                      *
*                                                                             *
*     [2] A.C.M. Beljaars, A.A.M. Holtslag (1991), Flux Parameterization over *
*           Land Surfaces for Atmospheric Models. J.Appl.Met. Vol. 30,pp 327- *
*           341                                                               *
*                                                                             *
*     Variables:                                                              *
*     L     = Monin-Obukhov-length [m]                                        *
*     z     = height [m]                                                      *
*     zeta  = auxiliary variable                                              *
*                                                                             *
*     Constants:                                                              *
*     eps   = 1.2E-38, SUN-underflow: to avoid division by zero errors        *
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * 

      include 'includepar'

      real psih,x,z,zeta,L,a,b,c,d,eps
      parameter(a=1.,b=0.667,c=5.,d=0.35,eps=1.e-20)

      if ((L.ge.0).and.(L.lt.eps)) then
        L=eps
      else if ((L.lt.0).and.(L.gt.(-1.*eps))) then          
        L=-1.*eps
      endif

      if ((log10(z)-log10(abs(L))).lt.log10(eps)) then
        psih=0.
      else
        zeta=z/L
        if (zeta.gt.0.) then
          psih = - (1.+0.667*a*zeta)**(1.5) - b*(zeta-c/d)*exp(-d*zeta)
     &           - b*c/d + 1.
        else
          x=(1.-16.*zeta)**(.25)
          psih=2.*log((1.+x*x)/2.)
        end if
      end if

      end
