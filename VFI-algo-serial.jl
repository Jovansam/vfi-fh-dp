
using Parameters
using QuantEcon: rouwenhorst
using Interpolations
using Optim

# transformation functions
# closed interval [a, b]
function tab(x; a = 0, b = 1)
    (b + a)/2 + (b - a)/2*((2x)/(1 + x^2))
end

# open interval (a, b)
function logit(x; a = 0, b = 1)
    (b - a) * (exp(x)/(1 + exp(x))) + a
end

function solvelast!(dp::NamedTuple, Ldict, Cdict, A1dict, Vdict)
    utility = dp.u
    grid_A = dp.grid_A
    n = dp.n
    w = dp.w
    r = dp.r
    T = dp.T
    β = dp.β
    ρ = dp.ρ
    σ = dp.σ
    μ = dp.μ

    # discretize ar(1) process in wages: rouwenhorst(n, ρ, σ, μ)
    mc = rouwenhorst(n, ρ, σ, μ)
    ξ = mc.state_values
    ℙ = mc.p

    for i in 1:n
        for s in 1:length(grid_A)
            # use bisection here
            opt = optimize(x -> -utility(x*(w[T] + ξ[i]) + grid_A[s]*(1+r), x), 0.0, 1.0)
            xstar = Optim.minimizer(opt)
            Ldict[s, i, T] = xstar
            A1dict[s, i, T] = 0.0
            Cdict[s, i, T] = (w[T] + ξ[i])*Ldict[s, i, T] + grid_A[s]*(1+r)
            Vdict[s, i, T] = -Optim.minimum(opt)
            convdict[s, i, T] = Optim.converged(opt)
        end
    end
    return Ldict, Cdict, A1dict, Vdict
end

function solverest!(dp::NamedTuple, Ldict, Cdict, A1dict, Vdict, convdict; t0::Int=1, alg=NewtonTrustRegion())
    utility = dp.u
    grid_A = dp.grid_A
    n = dp.n
    w = dp.w
    r = dp.r
    T = dp.T
    β = dp.β
    ρ = dp.ρ
    σ = dp.σ
    μ = dp.μ

    transf = tab

    # discretize ar(1) process in wages: rouwenhorst(n, ρ, σ, μ)
    mc = rouwenhorst(n, ρ, σ, μ)
    ξ = mc.state_values
    ℙ = mc.p

    for t in T-1:-1:t0
        #=@time=# for i in 1:n
            EV = LinearInterpolation( grid_A, sum(ℙ[i, i′] .* Vdict[:, i′, t+1] for i′ in 1:n), extrapolation_bc = Line() )
            for s in 1:length(grid_A)
                # skip optimization for situations in which consumption would be negative
                if (w[t] + ξ[i]) + grid_A[s] * (1+r) < 0 || Vdict[s, i, t+1] == -Inf
                    convdict[s, i, t] = true
                    Ldict[s, i, t] = -1000.0
                    A1dict[s, i, t] = -1000.0
                    Cdict[s, i, t] = -1000.0
                    Vdict[s, i, t] = -Inf
                    continue
                end
                # x[1] is assets to carry forward, x[2] is labor supply
                initial_x = [A1dict[s, i, t+1], 0.0]
                opt = optimize(x -> -( utility(transf(x[2])*(w[t] + ξ[i]) + grid_A[s]*(1+r) - x[1], transf(x[2])) + β*EV(x[1]) ),
                        initial_x,
                        alg,
                        Optim.Options(iterations=1_000, g_tol=1e-4, x_tol=1e-4, f_tol=1e-4))
                xstar = Optim.minimizer(opt)
                convdict[s, i, t] = Optim.converged(opt)
                Ldict[s, i, t] = transf(xstar[2])
                A1dict[s, i, t] = xstar[1]
                Cdict[s, i, t] = (w[t] + ξ[i])*Ldict[s, i, t] + grid_A[s]*(1+r)
                Vdict[s, i, t] = -Optim.minimum(opt)
            end
        end
        #println("period ", t, " finished")
    end
    return Ldict, Cdict, A1dict, Vdict, convdict
end

function solvemodel!(dp::NamedTuple, Ldict, Cdict, A1dict, Vdict, convdict; t0::Int=1, alg=NewtonTrustRegion())
    solvelast!(dp, Ldict, Cdict, A1dict, Vdict)
    solverest!(dp, Ldict, Cdict, A1dict, Vdict, convdict; t0=t0, alg=alg)
    return Ldict, Cdict, A1dict, Vdict, convdict
end

function utility(c, L)
    if c <= 0 || 1 - L <= 0
        return -1e9
    else
        return log(c) + log(1 - L)
    end
end

T = 65
w = Vector{Float64}(undef, T) # exogenous wages
w .= (900 .+ 20.0 .* (1:T) .- 0.5 .* (1:T).^2)

# create model object with default values for some parameters
Model = @with_kw (u=utility, n=5, w, r=0.05, T=65, β=0.95,
                                grid_A=-1_000:10.0:10_000, ρ=0.7, σ=15.0, μ=0.0)

dp = Model(w=w)

Vdict = Array{Float64}(undef, (length(dp.grid_A), dp.n, dp.T))
Cdict = Array{Float64}(undef, (length(dp.grid_A), dp.n, dp.T))
Ldict = Array{Float64}(undef, (length(dp.grid_A), dp.n, dp.T))
A1dict = Array{Float64}(undef, (length(dp.grid_A), dp.n, dp.T))
convdict = Array{Bool}(undef, (length(dp.grid_A), dp.n, dp.T))

#@time solvemodel!(dp, Ldict, Cdict, A1dict, Vdict, convdict);

#rmprocs(procs)