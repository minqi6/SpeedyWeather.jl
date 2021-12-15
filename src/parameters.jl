"""
Parameter struct that holds all parameters that define the default model setup.
With keywords such that default values can be changed at creation.
"""
@with_kw struct Params

    # NUMBER FORMATS
    NF::DataType=Float64    # number format

    # RESOLUTION
    nlat::Int=48            # number of latitudes
    nlon::Int=2nlat         # number of longitudes
    nlev::Int=8             # number of vertical levels
    trunc::Int=30           # spectral truncation
    ntracers::Int=1         # number of tracers (specific humidity is one)

    # PHYSICAL CONSTANTS
    R_earth::Real=6.371e6   # Radius of Earth [m]
    Ω::Real=7.292e-5        # Angular frequency of Earth's rotation [1/s]
    g::Real=9.81            # Gravitational acceleration [m/s^2]
    akap::Real=2/7          # Ratio of gas constant to specific heat of dry air
                            # at constant pressure = 1 - 1/γ where γ is the
                            # heat capacity ratio of a perfect diatomic gas (7/5)
    cp::Real=1004.0         # Specific heat at constant pressure [J/K/kg]
    R::Real=akap*cp         # Specific gas constant for dry air [J/kg/K]
    alhc::Real=2501.0       # Latent heat of condensation [J/g] for consistency with
                            # specific humidity [g/Kg]
    alhs::Real=2801.0       # Latent heat of sublimation [?]
    sbc::Real=5.67e-8       # Stefan-Boltzmann constant [W/m^2/K^4]

    # STANDARD ATMOSPHERE
    γ::Real=6.0             # Reference temperature lapse rate -dT/dz [K/km]
    Tabs_ref::Real=288      # Reference absolute temperature at surface z=0 [K]
    Tabs_top::Real=216      # Reference absolute temperature in stratosphere [K]
    hscale::Real=7.5        # Reference scale height for pressure [km]
    p0::Real=1e5            # Reference pressure [Pa]   TODO where is this needed?
    p0_ref::Real=1013       # Reference surface pressure [hPa]
    hshum::Real=2.5         # Reference scale height for specific humidity [km]
    rh_ref::Real=0.7        # Reference relative humidity of near-surface air
    es_ref::Real=17         # Reference saturation water vapour pressure [Pa]

    # VERTICAL COORDINATE
    # defined by a generalised logistic function, interpolating ECMWF's L31 configuration
    # change only for more levels in the stratosphere vs troposphere vs boundary layer
    GLcoefs::GenLogisticCoefs=GenLogisticCoefs()

    # DIFFUSION
    npowhd::Real=4          # Power of Laplacian in horizontal diffusion
    thd::Real=2.4           # Damping time [hrs] for diffusion (del^6) of temperature and vorticity
    thdd::Real=2.4          # Damping time [hrs] for diffusion (del^6) of divergence
    thds::Real=12           # Damping time [hrs] for extra diffusion (del^2) in the stratosphere
    tdrs::Real=24*30        # Damping time [hrs] for drag on zonal-mean wind in the stratosphere

    # PARAMETERIZATIONS
    seasonal_cycle::Bool=true   # Seasonal cycle?
    n_shortwave::Int=3          # Compute shortwave radiation every n steps
    sppt_on::Bool=false         # Turn on SPPT?

    # TIME STEPPING
    nstepsday::Int=36           # number of time steps in one day
    Δt::Real=86400/nstepsday    # time step in seconds
    ndays::Real=10              # number of days to integrate for

    # NUMERICS
    robert_filter::Real=0.05    # Robert (1966) time filter coefficeint for suppress comput. mode
    williams_filter::Real=0.53  # Williams time filter (Amezcua 2011) coefficient for 3rd order acc
    α::Real=0.5                 # coefficient for semi-implicit computations
                                # 0 -> forward step for gravity wave terms,
                                # 1 -> backward implicit
                                # 0.5 -> centered implicit

    # BOUNDARY FILES
    boundary_path::String=""    # package location is default
    boundary_file::String="surface.nc"

    # INITIAL CONDITIONS
    initial_conditions::Symbol=:rest    # :rest or :restart

    # OUTPUT
    verbose::Bool=true          # print dialog for feedback
    output::Bool=false          # Store data in netCDF?
    output_dt::Real=6           # output time step [hours]
    outpath::String=pwd()       # path to output folder

    # TODO assert not allowed parameter values
    @assert α in [0,0.5,1] "Only semi-implicit α = 0, 0.5 or 1 allowed."
end

"""Coefficients of the generalised logistic function to describe the vertical coordinate.
Default coefficients A,K,C,Q,B,M,ν are fitted to the old L31 configuration at ECMWF.
See geometry.jl and function vertical_coordinate for more informaiton.

Following the notation of https://en.wikipedia.org/wiki/Generalised_logistic_function (Dec 15 2021)."""
@with_kw struct GenLogisticCoefs
    A::Real=-0.283     # obtained from a fit in /input_date/vertical_coordinate/vertical_resolution.ipynb
    K::Real= 0.871
    C::Real= 0.414
    Q::Real= 6.695
    B::Real=10.336
    M::Real= 0.602
    ν::Real= 5.812
end