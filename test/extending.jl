@testset "Extending forcing and drag" begin
    @kwdef struct JetDrag{NF} <: SpeedyWeather.AbstractDrag

        # DIMENSIONS from SpectralGrid
        "Spectral resolution as max degree of spherical harmonics"
        trunc::Int
    
        # OPTIONS
        "Relaxation time scale τ"
        time_scale::Second = Day(6)
    
        "Jet strength [m/s]"
        u₀::NF = 20
    
        "latitude of Gaussian jet [˚N]"
        latitude::NF = 30
    
        "Width of Gaussian jet [˚]"
        width::NF = 6
    
        # TO BE INITIALISED
        "Relaxation back to reference vorticity"
        ζ₀::LowerTriangularMatrix{Complex{NF}} = zeros(LowerTriangularMatrix{Complex{NF}}, trunc+2, trunc+1)
    end
    
    function JetDrag(SG::SpectralGrid; kwargs...)
        return JetDrag{SG.NF}(; SG.trunc, kwargs...)
    end
    
    function SpeedyWeather.initialize!( drag::JetDrag,
                                        model::AbstractModel)
    
        (; spectral_grid, geometry) = model
        (; Grid, NF, nlat_half) = spectral_grid
        u = zeros(Grid{NF}, nlat_half)
    
        lat = geometry.latds
    
        for ij in eachindex(u)
            u[ij] = drag.u₀ * exp(-(lat[ij]-drag.latitude)^2/(2*drag.width^2))
        end
    
        û = SpeedyTransforms.transform(u, model.spectral_transform)
        v̂ = zero(û)
        SpeedyTransforms.curl!(drag.ζ₀, û, v̂, model.spectral_transform)
        return nothing
    end
    
    function SpeedyWeather.drag!(
        diagn::DiagnosticVariables,
        progn::PrognosticVariables,
        drag::JetDrag,
        model::AbstractModel,
        lf::Integer,
    )
    
        vor = progn.vor[lf]
        (; vor_tend) = diagn.tendencies
        (; ζ₀) = drag
        
        (; radius) = model.spectral_grid
        r = radius/drag.time_scale.value

        k = diagn.nlayers   # drag only on surface layer
        for lm in eachharmonic(vor_tend)
            vor_tend[lm, k] -= r*(vor[lm, k] - ζ₀[lm])
        end
    end
    
    @kwdef struct StochasticStirring{NF} <: SpeedyWeather.AbstractForcing
        
        # DIMENSIONS from SpectralGrid
        "Spectral resolution as max degree of spherical harmonics"
        trunc::Int
        
        "Number of latitude rings, used for latitudinal mask"
        nlat::Int
    
        
        # OPTIONS
        "Decorrelation time scale τ [days]"
        decorrelation_time::Second = Day(2)
    
        "Stirring strength A [1/s²]"
        strength::NF = 1e-11
    
        "Stirring latitude [˚N]"
        latitude::NF = 45
    
        "Stirring width [˚]"
        width::NF = 24
    
        "Minimum degree of spherical harmonics to force"
        lmin::Int = 8

        "Maximum degree of spherical harmonics to force"
        lmax::Int = 40

        "Minimum order of spherical harmonics to force"
        mmin::Int = 4

        "Maximum order of spherical harmonics to force"
        mmax::Int = lmax
        
        # TO BE INITIALISED
        "Stochastic stirring term S"
        S::LowerTriangularMatrix{Complex{NF}} = zeros(LowerTriangularMatrix{Complex{NF}}, trunc+2, trunc+1)
        
        "a = A*sqrt(1 - exp(-2dt/τ)), the noise factor times the stirring strength [1/s²]"
        a::Base.RefValue{NF} = Ref(zero(NF))
            
        "b = exp(-dt/τ), the auto-regressive factor [1]"
        b::Base.RefValue{NF} = Ref(zero(NF))
            
        "Latitudinal mask, confined to mid-latitude storm track by default [1]"
        lat_mask::Vector{NF} = zeros(NF, nlat)
    end
    
    function StochasticStirring(SG::SpectralGrid; kwargs...)
        (; trunc, nlat) = SG
        return StochasticStirring{SG.NF}(; trunc, nlat, kwargs...)
    end
    
    function SpeedyWeather.initialize!( forcing::StochasticStirring,
                                        model::AbstractModel)
        
        # precompute forcing strength, scale with radius^2 as is the vorticity equation
        (; radius) = model.spectral_grid
        A = radius^2 * forcing.strength
        
        # precompute noise and auto-regressive factor, packed in RefValue for mutability
        dt = model.time_stepping.Δt_sec
        τ = forcing.decorrelation_time.value    # in seconds
        forcing.a[] = A*sqrt(1 - exp(-2dt/τ))
        forcing.b[] = exp(-dt/τ)
        
        # precompute the latitudinal mask
        (; Grid, nlat_half) = model.spectral_grid
        latd = RingGrids.get_latd(Grid, nlat_half)
        
        for j in eachindex(forcing.lat_mask)
            # Gaussian centred at forcing.latitude of width forcing.width
            forcing.lat_mask[j] = exp(-(forcing.latitude-latd[j])^2/forcing.width^2*2)
        end
    
        return nothing
    end
    
    function SpeedyWeather.forcing!(
        diagn::DiagnosticVariables,
        progn::PrognosticVariables,
        forcing::StochasticStirring,
        model::AbstractModel,
        lf::Integer,
    )
        SpeedyWeather.forcing!(diagn, forcing, model.spectral_transform)
    end
    
    function SpeedyWeather.forcing!(
        diagn::DiagnosticVariables,
        forcing::StochasticStirring{NF},
        spectral_transform::SpectralTransform,
    ) where NF
        # noise and auto-regressive factors
        a = forcing.a[]    # = sqrt(1 - exp(-2dt/τ))
        b = forcing.b[]    # = exp(-dt/τ)
        
        (; S) = forcing
        lmax, mmax = size(S, as=Matrix)

        @inbounds for m in 1:mmax
            for l in m:lmax
                if (forcing.mmin <= m <= forcing.mmax) &&
                    (forcing.lmin <= l <= forcing.lmax)
                    # Barnes and Hartmann, 2011 Eq. 2
                    Qi = 2rand(Complex{NF}) - (1 + im)   # ~ [-1, 1] in complex
                    S[l, m] = a*Qi + b*S[l, m]
                end
            end
        end
    
        # to grid-point space
        S_grid = diagn.dynamics.a_2D_grid
        transform!(S_grid, S, spectral_transform)
        
        # mask everything but mid-latitudes
        RingGrids._scale_lat!(S_grid, forcing.lat_mask)
        
        # back to spectral space
        S_masked = diagn.dynamics.a_2D
        transform!(S_masked, S_grid, spectral_transform)
        k = diagn.nlayers       # only force surface layer
        diagn.tendencies.vor_tend[:, k] .+= S_masked
        return nothing
    end

    spectral_grid = SpectralGrid(trunc=31, nlayers=1)
    
    drag = JetDrag(spectral_grid, time_scale=Day(6))
    forcing = StochasticStirring(spectral_grid)
    initial_conditions = StartFromRest()

    # with barotropic model
    model = BarotropicModel(spectral_grid; initial_conditions, forcing, drag)
    simulation = initialize!(model)

    run!(simulation, period=Day(5))
    @test simulation.model.feedback.nars_detected == false

    # with shallow water model
    model = ShallowWaterModel(spectral_grid; initial_conditions, forcing, drag)
    simulation = initialize!(model)

    run!(simulation, period=Day(5))
    @test simulation.model.feedback.nars_detected == false
end