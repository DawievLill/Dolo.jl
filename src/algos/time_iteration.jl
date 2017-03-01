function residual(model, dprocess, s, x::Array{Array{Float64,2},1}, p, dr)
    N = size(s, 1)
    res = [zeros(size(x[1])) for i=1:length(x)]
    S = zeros(size(s))
    # X = zeros(size(x[1]))
    for i=1:size(res, 1)
        m = node(dprocess, i)
        for j=1:n_inodes(dprocess, i)
            M = inode(dprocess, i, j)
            w = iweight(dprocess, i, j)
            # Update the states
            for n=1:N
                S[n, :] = Dolo.transition(model, m, s[n, :], x[i][n, :], M, p)
            end

            X = dr(i, j, S)
            for n=1:N
                res[i][n, :] += w*Dolo.arbitrage(model, m, s[n, :], x[i][n, :], M, S[n, :], X[n, :], p)
            end
        end
    end
    return res
end


function residual(model, dprocess, s, x::Array{Float64,2}, p, dr)
    n_m = max(1, n_nodes(dprocess))
    xx = destack(x, n_m)
    res = residual(model, dprocess, s, xx, p, dr)
    return stack(res)
end

function destack(x::Array{Float64,2}, n_m::Int)
    N = div(size(x, 1), n_m)
    xx = reshape(x, N, n_m, size(x, 2))
    return Array{Float64,2}[xx[:, i, :] for i=1:n_m]
end

function stack(x::Array{Array{Float64,2},1})::Array{Float64,2}
     return cat(1, x...)
end

function time_iteration(model, process, init_dr; verbose::Bool=true,
    maxit::Int=100, tol::Float64=1e-8
    )

    # get grid for endogenous
    gg = model.options.grid
    grid = CartesianGrid(gg.a, gg.b, gg.orders)  # temporary compatibility

    endo_nodes = nodes(grid)
    N = size(endo_nodes, 1)
    n_s_endo = size(endo_nodes,2)

    dprocess = discretize(process)
    n_s_exo = n_nodes(dprocess)

    # initial guess
    # number of smooth decision rules
    nsd = max(n_nodes(dprocess), 1)

    p = model.calibration[:parameters]

    x0 = [init_dr(i, endo_nodes) for i=1:nsd]

    n_x = length(model.calibration[:controls])
    lb = Array(Float64, N*nsd, n_x)
    ub = Array(Float64, N*nsd, n_x)
    ix = 0
    for i in 1:nsd
        node_i = node(dprocess, i)
        for n in 1:N
            ix += 1
            endo_n = endo_nodes[n, :]
            lb[ix, :] = Dolo.controls_lb(model, node_i, endo_n, p)
            ub[ix, :] = Dolo.controls_ub(model, node_i, endo_n, p)
        end
    end

    # create decision rule (which interpolates x0)
    dr = CachedDecisionRule(dprocess, grid, x0)

    # loop option
    init_res = residual(model, dprocess, endo_nodes, x0, p, dr)
    it = 0
    err = maxabs(stack(init_res))
    err_0 = err

    verbose && @printf "%-6s%-12s%-12s%-5s\n" "It" "SA" "gain" "nit"
    verbose && println(repeat("-", 35))
    verbose && @printf "%-6i%-12.2e%-12.2e%-5i\n" 0 err NaN 0

    while it<maxit && err>tol

        it += 1

        set_values!(dr, x0)

        xx0 = stack(x0)
        fobj(u) = residual(model, dprocess, endo_nodes, u, p, dr)
        xx1, nit = serial_solver(fobj, xx0, lb, ub, maxit=10, verbose=false)
        x1 = destack(xx1, nsd)

        err = maxabs(xx1 - xx0)
        copy!(x0, x1)
        gain = err / err_0
        err_0 = err

        verbose && @printf "%-6i%-12.2e%-12.2e%-5i\n" it err gain nit
    end

    # TODO: somehow after defining `fobj` the `dr` object gets `Core.Box`ed
    #       making the return type right here non-inferrable.
    return dr

end

# get stupid initial rule
function time_iteration(model, process::AbstractExogenous; kwargs...)
    init_dr = ConstantDecisionRule(model.calibration[:controls])
    return time_iteration(model, process, init_dr;  kwargs...)
end

function time_iteration(model, init_dr::AbstractDecisionRule; kwargs...)
    process = model.exogenous
    return time_iteration(model, process, init_dr; kwargs...)
end

function time_iteration(model; kwargs...)
    process = model.exogenous
    init_dr = ConstantDecisionRule(model.calibration[:controls])
    return time_iteration(model, process, init_dr; kwargs...)
end