# -*- Mode: Python -*-
"""
Polynomial base functions and related utilities.
"""
cimport cython

cimport numpy as np
import numpy as np

cimport sfepy.discrete.common.extmods._fmfield as _f
from sfepy.discrete.common.extmods._fmfield cimport FMField

from sfepy.discrete.common.extmods.types cimport int32, float64, complex128

cdef extern from 'math.h':
    cdef float64 sqrt(float x)

cdef extern from 'common.h':
    void *pyalloc(size_t size)
    void pyfree(void *pp)
    int Max_i 'Max'(int a, int b)
    double Max_f 'Max'(double a, double b)
    double Min_f 'Min'(double a, double b)

cdef extern from 'lagrange.h':
    ctypedef struct LagrangeContext:
        int32 (*get_xi_dist)(float64 *pdist, FMField *xi,
                             FMField *point, FMField *e_coors,
                             void *_ctx)
        int32 (*eval_basis)(FMField *out, FMField *coors, int32 diff,
                            void *_ctx)
        int32 iel # >= 0 => apply reference mapping to gradient.

        LagrangeContext *geo_ctx

        int32 order
        int32 is_bubble
        int32 tdim
        int32 *nodes
        int32 n_nod
        int32 n_col

        FMField ref_coors[1]
        float64 vmin
        float64 vmax

        FMField mesh_coors[1]
        int32 *mesh_conn
        int32 n_cell
        int32 n_cp

        FMField mtx_i[1]

        FMField *bc
        FMField base1d[1]
        FMField mbfg[1]

        float64 eps
        int32 check_errors
        int32 i_max
        float64 newton_eps

    void _print_context_lagrange \
         'print_context_lagrange'(LagrangeContext *ctx)

    int32 _get_barycentric_coors \
          'get_barycentric_coors'(FMField *bc, FMField *coors,
                                  LagrangeContext *ctx)

    int32 _get_xi_dist \
          'get_xi_dist'(float64 *pdist, FMField *xi,
                        FMField *point, FMField *e_coors,
                        void *_ctx)

    int32 _get_xi_simplex \
          'get_xi_simplex'(FMField *xi, FMField *dest_point, FMField *e_coors,
                           LagrangeContext *ctx)

    int32 _get_xi_tensor \
          'get_xi_tensor'(FMField *xi, FMField *dest_point, FMField *e_coors,
                          LagrangeContext *ctx)

    int32 _eval_basis_lagrange \
          'eval_basis_lagrange'(FMField *out, FMField *coors, int32 diff,
                                void *_ctx)

    int32 _eval_lagrange_simplex \
          'eval_lagrange_simplex'(FMField *out, int32 order, int32 diff,
                                  LagrangeContext *ctx)

    int32 _eval_lagrange_tensor_product \
          'eval_lagrange_tensor_product'(FMField *out, int32 order, int32 diff,
                                         LagrangeContext *ctx)

cdef class CLagrangeContext:

    cdef LagrangeContext *ctx

    # Store arrays to prevent their deallocation in Python.
    cdef readonly CLagrangeContext _geo_ctx
    cdef readonly np.ndarray mesh_coors
    cdef readonly np.ndarray mesh_conn
    cdef readonly np.ndarray base1d # Auxiliary buffer.
    cdef readonly np.ndarray mbfg # Auxiliary buffer.

    property is_bubble:

        def __get__(self):
            return self.ctx.is_bubble

        def __set__(self, int32 is_bubble):
            self.ctx.is_bubble = is_bubble

    property iel:

        def __get__(self):
            return self.ctx.iel

        def __set__(self, int32 iel):
            assert iel < self.ctx.n_cell
            self.ctx.iel = iel

    property geo_ctx:

        def __set__(self, _ctx):
            cdef CLagrangeContext __ctx = <CLagrangeContext> _ctx
            cdef LagrangeContext *ctx = <LagrangeContext *> __ctx.ctx

            self._geo_ctx = __ctx
            self.ctx.geo_ctx = ctx

    def __cinit__(self,
                  int32 order=1,
                  int32 is_bubble=0,
                  int32 tdim=0,
                  np.ndarray[int32, mode='c', ndim=2] nodes=None,
                  np.ndarray[float64, mode='c', ndim=2] ref_coors=None,
                  np.ndarray mesh_coors=None,
                  np.ndarray mesh_conn=None,
                  np.ndarray[float64, mode='c', ndim=2] mtx_i=None,
                  float64 eps=1e-15,
                  int32 check_errors=0,
                  int32 i_max=100,
                  float64 newton_eps=1e-8):
        cdef LagrangeContext *ctx
        cdef np.ndarray[float64, mode='c', ndim=2] _mesh_coors
        cdef np.ndarray[int32, mode='c', ndim=2] _mesh_conn
        cdef np.ndarray[float64, mode='c', ndim=1] _base1d

        ctx = self.ctx = <LagrangeContext *> pyalloc(sizeof(LagrangeContext))

        if ctx is NULL:
            raise MemoryError()

        ctx.get_xi_dist = &_get_xi_dist
        ctx.eval_basis = &_eval_basis_lagrange
        ctx.iel = -1

        ctx.order = order
        ctx.is_bubble = is_bubble

        ctx.tdim = tdim if tdim > 0 else ref_coors.shape[1]

        if nodes is not None:
            ctx.nodes = &nodes[0, 0]
            ctx.n_nod = nodes.shape[0]
            ctx.n_col = nodes.shape[1]

            _base1d = self.base1d = np.zeros((ctx.n_nod,), dtype=np.float64)
            _f.fmf_pretend_nc(ctx.base1d, 1, 1, 1, ctx.n_nod, &_base1d[0])

            _mbfg = self.mbfg = np.zeros((ref_coors.shape[1], ctx.n_nod),
                                         dtype=np.float64)
            _f.array2fmfield2(ctx.mbfg,_mbfg)

        else:
            raise ValueError('nodes argument is required!')

        if ref_coors is not None:
            _f.array2fmfield2(ctx.ref_coors, ref_coors)

            ctx.vmin = ref_coors[0, 0]
            ctx.vmax = ref_coors[1, 0]

        else:
            raise ValueError('ref_coors argument is required!')

        if mesh_coors is not None:
            _mesh_coors = self.mesh_coors = mesh_coors
            _f.array2fmfield2(ctx.mesh_coors, _mesh_coors)

        else:
            _f.fmf_pretend_nc(ctx.mesh_coors, 0, 0, 0, 0, NULL)

        if mesh_conn is not None:
            _mesh_conn = self.mesh_conn = mesh_conn

            ctx.mesh_conn = &_mesh_conn[0, 0]
            ctx.n_cell = mesh_conn.shape[0]
            ctx.n_cp = mesh_conn.shape[1]

        else:
            ctx.mesh_conn = NULL
            ctx.n_cell = ctx.n_cp = 0

        if mtx_i is not None:
            _f.array2fmfield2(ctx.mtx_i, mtx_i)

        else:
            raise ValueError('mtx_i argument is required!')

        ctx.eps = eps
        ctx.check_errors = check_errors

        ctx.i_max = i_max
        ctx.newton_eps = newton_eps

    def __dealloc__(self):
        pyfree(self.ctx)

    def __str__(self):
        return 'CLagrangeContext'

    def cprint(self):
        _print_context_lagrange(self.ctx)

    def evaluate(self, np.ndarray[float64, mode='c', ndim=2] coors not None,
                 int32 diff=False,
                 float64 eps=1e-15,
                 int32 check_errors=True):
        cdef int32 n_coor = coors.shape[0]
        cdef int32 n_nod = self.ctx.n_nod
        cdef int32 dim = coors.shape[1]
        cdef int32 bdim, n_v
        cdef FMField _out[1], _coors[1]

        ctx = self.ctx

        n_v = ctx.ref_coors.nRow

        ctx.check_errors = check_errors
        ctx.eps = eps

        if diff:
            bdim = dim

        else:
            bdim = 1

        cdef np.ndarray[float64, ndim=3] out = np.zeros((n_coor, bdim, n_nod),
                                                        dtype=np.float64)

        _f.array2fmfield3(_out, out)
        _f.array2fmfield2(_coors, coors)

        self.ctx.eval_basis(_out, _coors, diff, ctx)

        return out

@cython.boundscheck(False)
def get_barycentric_coors(np.ndarray[float64, mode='c', ndim=2] coors not None,
                          np.ndarray[float64, mode='c', ndim=2] mtx_i not None,
                          float64 eps=1e-8,
                          int check_errors=False):
    """
    Get barycentric (area in 2D, volume in 3D) coordinates of points.

    Parameters
    ----------
    coors : array
        The coordinates of the points, shape `(n_coor, dim)`.
    mtx_i : array
        The inverse of simplex coordinates matrix, shape `(dim + 1, dim + 1)`.
    eps : float
        The tolerance for snapping out-of-simplex point back to the simplex.
    check_errors : bool
        If True, raise ValueError if a barycentric coordinate is outside
        the snap interval `[-eps, 1 + eps]`.

    Returns
    -------
    bc : array
        The barycentric coordinates, shape `(n_coor, dim + 1)`. Then
        reference element coordinates `xi = dot(bc, ref_coors)`.
    """
    cdef int n_coor = coors.shape[0]
    cdef int n_v = mtx_i.shape[0]
    cdef LagrangeContext ctx[1]
    cdef FMField _coors[1]
    cdef np.ndarray[float64, ndim=2] bc = np.zeros((n_coor, n_v),
                                                   dtype=np.float64)

    ctx.eps = eps
    ctx.check_errors = check_errors
    _f.array2fmfield2(ctx.bc, bc)
    _f.array2fmfield2(ctx.mtx_i, mtx_i)
    _f.array2fmfield2(_coors, coors)

    _get_barycentric_coors(ctx.bc, _coors, ctx)
    return bc

@cython.boundscheck(False)
def eval_lagrange_simplex(np.ndarray[float64, mode='c', ndim=2] coors not None,
                          np.ndarray[float64, mode='c', ndim=2] mtx_i not None,
                          np.ndarray[int32, mode='c', ndim=2] nodes not None,
                          int order, int diff=False,
                          float64 eps=1e-15,
                          int check_errors=True):
    """
    Evaluate Lagrange base polynomials in given points on simplex domain.

    Parameters
    ----------
    coors : array
        The coordinates of the points, shape `(n_coor, dim)`.
    mtx_i : array
        The inverse of simplex coordinates matrix, shape `(dim + 1, dim + 1)`.
    nodes : array
        The description of finite element nodes, shape `(n_nod, dim + 1)`.
    order : int
        The polynomial order.
    diff : bool
        If True, return base function derivatives.
    eps : float
        The tolerance for snapping out-of-simplex point back to the simplex.
    check_errors : bool
        If True, raise ValueError if a barycentric coordinate is outside
        the snap interval `[-eps, 1 + eps]`.

    Returns
    -------
    out : array
        The evaluated base functions, shape `(n_coor, 1 or dim, n_nod)`.
    """
    cdef int bdim
    cdef int n_coor = coors.shape[0]
    cdef int dim = mtx_i.shape[0] - 1
    cdef int n_nod = nodes.shape[0]
    cdef LagrangeContext ctx[1]
    cdef FMField _out[1], _coors[1]
    cdef np.ndarray[float64, ndim=2] bc = np.zeros((n_coor, dim + 1),
                                                   dtype=np.float64)

    assert mtx_i.shape[0] == nodes.shape[1]

    if diff:
        bdim = dim

    else:
        bdim = 1

    cdef np.ndarray[float64, ndim=3] out = np.zeros((n_coor, bdim, n_nod),
                                                    dtype=np.float64)

    ctx.eps = eps
    ctx.check_errors = check_errors
    ctx.nodes = &nodes[0, 0]
    ctx.n_col = nodes.shape[1]
    _f.array2fmfield2(ctx.bc, bc)
    _f.array2fmfield2(ctx.mtx_i, mtx_i)
    _f.array2fmfield3(_out, out)
    _f.array2fmfield2(_coors, coors)

    _get_barycentric_coors(ctx.bc, _coors, ctx)
    _eval_lagrange_simplex(_out, order, diff, ctx)

    return out

@cython.boundscheck(False)
def eval_lagrange_tensor_product(np.ndarray[float64, mode='c', ndim=2]
                                 coors not None,
                                 np.ndarray[float64, mode='c', ndim=2]
                                 mtx_i not None,
                                 np.ndarray[int32, mode='c', ndim=2]
                                 nodes not None,
                                 int order, int diff=False,
                                 float64 eps=1e-15,
                                 int check_errors=True):
    """
    Evaluate Lagrange base polynomials in given points on tensor product
    domain.

    Parameters
    ----------
    coors : array
        The coordinates of the points, shape `(n_coor, dim)`.
    mtx_i : array
        The inverse of 1D simplex coordinates matrix, shape `(2, 2)`.
    nodes : array
        The description of finite element nodes, shape `(n_nod, 2 * dim)`.
    order : int
        The polynomial order.
    diff : bool
        If True, return base function derivatives.
    eps : float
        The tolerance for snapping out-of-simplex point back to the simplex.
    check_errors : bool
        If True, raise ValueError if a barycentric coordinate is outside
        the snap interval `[-eps, 1 + eps]`.

    Returns
    -------
    out : array
        The evaluated base functions, shape `(n_coor, 1 or dim, n_nod)`.
    """
    cdef int ii, idim, im, ic
    cdef int n_coor = coors.shape[0]
    cdef int n_nod = nodes.shape[0]
    cdef int dim = coors.shape[1]
    cdef LagrangeContext ctx[1]
    cdef FMField _out[1], _coors[1]
    cdef int32 *_nodes = &nodes[0, 0]
    cdef np.ndarray[float64, ndim=3] bc = np.zeros((dim, n_coor, 2),
                                                   dtype=np.float64)
    cdef np.ndarray[float64, ndim=3] base1d = np.zeros((n_coor, 1, n_nod),
                                                       dtype=np.float64)
    if diff:
        bdim = dim

    else:
        bdim = 1

    cdef np.ndarray[float64, ndim=3] out = np.zeros((n_coor, bdim, n_nod),
                                                    dtype=np.float64)

    ctx.eps = eps
    ctx.check_errors = check_errors
    ctx.nodes = &nodes[0, 0]
    ctx.n_col = nodes.shape[1]
    _f.array2fmfield2(ctx.mtx_i, mtx_i)
    _f.array2fmfield3(ctx.base1d, base1d)
    _f.fmf_pretend_nc(ctx.bc, dim, 1, n_coor, 2, &bc[0, 0, 0])
    _f.array2fmfield3(_out, out)

    for ii in range(0, dim):
        _f.FMF_SetCell(ctx.bc, ii)
         # slice [:,ii:ii+1]
        _f.fmf_pretend_nc(_coors, 1, 1, coors.shape[0], coors.shape[1],
                          &coors[0, ii])
        _get_barycentric_coors(ctx.bc, _coors, ctx)

    _eval_lagrange_tensor_product(_out, order, diff, ctx)

    return out
