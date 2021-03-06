      subroutine drydepokernel(nunc,deposit,x,y,nage)
C                               i      i    i i  i
********************************************************************************
*                                                                              *
*     Attribution of the deposition to the grid using a uniform kernel with    *
*     bandwidths dx and dy.                                                    *
*                                                                              *
*     Author: A. Stohl                                                         *
*                                                                              *
*     26 December 1996                                                         *
*                                                                              *
********************************************************************************
*                                                                              *
* Variables:                                                                   *
*                                                                              *
* nunc             uncertainty class of the respective particle                *
* nage             age class of the respective particle                        *
* deposit          amount (kg) to be deposited                                 *
*                                                                              *
********************************************************************************

      include 'includepar'
      include 'includecom'


      real x,y,deposit(maxspec),ddx,ddy,xl,yl,wx,wy,w
      integer ix,jy,ixp,jyp,k,nunc,nage
   

      xl=(x*dx+xoutshift)/dxout
      yl=(y*dy+youtshift)/dyout
      ix=int(xl)
      jy=int(yl)
      ddx=xl-float(ix)                   ! distance to left cell border
      ddy=yl-float(jy)                   ! distance to lower cell border

      if (ddx.gt.0.5) then
        ixp=ix+1
        wx=1.5-ddx
      else
        ixp=ix-1
        wx=0.5+ddx
      endif

      if (ddy.gt.0.5) then
        jyp=jy+1
        wy=1.5-ddy
      else
        jyp=jy-1
        wy=0.5+ddy
      endif


C Determine mass fractions for four grid points
***********************************************

      if ((ix.ge.0).and.(jy.ge.0).and.(ix.le.numxgrid-1).and.
     +(jy.le.numygrid-1)) then
        w=wx*wy
        do 22 k=1,nspec
          if (DRYDEPSPEC(k)) drygridunc(ix,jy,k,nunc,nage)=
     +    drygridunc(ix,jy,k,nunc,nage)+deposit(k)*w
22        continue
      endif

      if ((ixp.ge.0).and.(jyp.ge.0).and.(ixp.le.numxgrid-1).and.
     +(jyp.le.numygrid-1)) then
        w=(1.-wx)*(1.-wy)
        do 23 k=1,nspec
          if (DRYDEPSPEC(k)) drygridunc(ixp,jyp,k,nunc,nage)=
     +    drygridunc(ixp,jyp,k,nunc,nage)+deposit(k)*w
23        continue
      endif

      if ((ixp.ge.0).and.(jy.ge.0).and.(ixp.le.numxgrid-1).and.
     +(jy.le.numygrid-1)) then
        w=(1.-wx)*wy
        do 24 k=1,nspec
          if (DRYDEPSPEC(k)) drygridunc(ixp,jy,k,nunc,nage)=
     +    drygridunc(ixp,jy,k,nunc,nage)+deposit(k)*w
24        continue
      endif

      if ((ix.ge.0).and.(jyp.ge.0).and.(ix.le.numxgrid-1).and.
     +(jyp.le.numygrid-1)) then
        w=wx*(1.-wy)
        do 25 k=1,nspec
          if (DRYDEPSPEC(k)) drygridunc(ix,jyp,k,nunc,nage)=
     +    drygridunc(ix,jyp,k,nunc,nage)+deposit(k)*w
25        continue
      endif

      end
