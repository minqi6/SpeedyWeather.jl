"""
Struct that holds the boundary arrays.
"""
struct Boundaries{NF<:AbstractFloat,Grid<:AbstractGrid{NF}} # number format NF
    orography   ::Grid                                  # orography [m]
    geopot_surf ::LowerTriangularMatrix{Complex{NF}}    # surface geopotential (=orography*gravity) [m^2/s^2]

    # landsea_mask    ::Array{NF,2}           # land-sea mask
    # albedo          ::Array{NF,2}           # annual mean surface albedo
end

""" Generator function for a Boundaries struct. Loads the boundary conditions,
orography, land-sea mask and albedo from an netCDF file and stores the in a
`Boundaries` struct."""
function Boundaries(P::Parameters,S::SpectralTransform{NF}) where NF

    @unpack orography_path, orography_file, gravity = P
    @unpack Grid, lmax, mmax = S

    # LOAD NETCDF FILE (but not its data yet)
    if orography_path == ""
        path = joinpath(@__DIR__,"../input_data",orography_file)
    else
        path = joinpath(orography_path,orography_file)
    end
    ncfile = NetCDF.open(path)


    if P.model <: Barotropic   # no boundary data needed with the barotropic model
        
        # create dummy arrays
        orography   = zeros(Grid{NF},0)
        geopot_surf = zeros(LowerTriangularMatrix{Complex{NF}},0,0)

    elseif P.model <: ShallowWater || P.model <: PrimitiveEquation

        # OROGRAPHY
        orography_highres = ncfile.vars["orog"][:,:]        # height [m]

        # Interpolate/coarsen to desired resolution
        #TODO also read lat,lon from file and flip array in case it's not as expected
        recompute_legendre = true
        orography_spec = spectral(orography_highres;Grid=FullGaussianGrid,recompute_legendre)

        lmax,mmax = P.trunc,P.trunc
        orography_spec = spectral_truncation(orography_spec,lmax+1,mmax)
        orography = gridded(orography_spec,S)

        # SURFACE GEOPOTENTIAL
        geopot_surf = zeros(LowerTriangularMatrix{Complex{NF}},0,0)

    else # primitive equation model only

        # READ, TODO check which latitude ordering is required, it's North to South in file
        # orography = ncfile.vars["orog"][:,:]        # height [m]
        # landsea_mask = ncfile.vars["lsm"][:,:]    # fraction of land [0-1]
        # albedo = ncfile.vars["alb"][:,:]          # annual-mean albedo [0-1]

        # GEOPOTENTIAL, transform to spectral space and truncate accordingly   
        # geopot_surf_highres = spectral(gravity*orography)
        # geopot_surf = spectral_truncation(geopot_surf_highres,  # truncate to
        #                                     P.trunc+1,P.trunc)  # lmax+1,mmax matrix
        # spectral_truncation!(geopot_surf,P.trunc)               # but set l=lmax+1 row to zero
        # geopot_surf_grid = gridded(geopot_surf)
    end

    # convert to number format NF here
    return Boundaries(orography,geopot_surf)#,landsea_mask,albedo)
end