function add_epsilon!(x::ListOfPoints{d}, i, epsilon) where d
  ei = SVector{d,Float64}([(j==i?epsilon:0.0) for j=1:d])
  for i=1:length(x)
    x[i] += ei
  end
end

function DiffFun(fun, x0::Vector{ListOfPoints{n_x}}, epsilon=1e-6) where n_x
    xi = deepcopy(x0)
    N = length(x0[1])
    n_m = length(x0)
    r0 = fun(x0)
    JMat = [zeros(n_x, n_x, N) for i=1:n_m]
    for i_x=1:n_x
      xi = deepcopy(x0)
      for i_m=1:n_m
        add_epsilon!(xi[i_m], i_x, epsilon)
      end
      di = (fun(xi)-r0)/epsilon
      for i_m=1:n_m
        JMat[i_m][:,i_x,:] = reinterpret(Float64, di[i_m], (n_x, N))
        # add_epsilon!(xi[i_m], i, -epsilon)
      end
    end
    J = [reinterpret(SMatrix{n_x,n_x,Float64,n_x^2},JMat[i],(N,)) for i=1:n_m]
    return r0,J
end


function newton(fun::Function, x0::Vector{ListOfPoints{n_x}}, a::Vector{ListOfPoints{n_x}}, b::Vector{ListOfPoints{n_x}}; maxit=10, verbose=false, n_bsteps=5, lam_bsteps=0.5) where n_x

    steps = (lam_bsteps).^collect(0:n_bsteps)

    n_m = length(x0)
    N = length(x0[1])
    x = x0
    err_0 = -1.0

    for i=1:maxit
        R_i, D_i = DiffFun(fun, x)
        PhiPhi!(R_i,x,a,b,D_i)
        new_err = maxabs(R_i)
        dx = [[D_i[i][n]\R_i[i][n] for n=1:N] for i=1:n_m]
        err_x = maxabs(dx)
        i_bckstps = 0
        while new_err>=err_0 && i_bckstps<length(steps)
            i_bckstps += 1
            new_x = x-dx*steps[i_bckstps]
            new_res = fun(new_x) # no diff
            new_res = [PhiPhi0.(new_res[i],new_x[i],a[i],b[i]) for i=1:n_m]
            new_err = maxabs(new_res)
        end
        err_0 = new_err
        x = x - dx
        println(i_bckstps, " : ", err_x, " : ", new_err, )
    end

    nit = maxit
    return x, nit





    # return x

end



function smooth(x::AbstractMatrix{Float64}, a::AbstractMatrix{Float64},
                b::AbstractMatrix{Float64}, fx::AbstractMatrix{Float64})

    BIG = 1e20

    da = a - x
    db = b - x

    dainf = a .<= -BIG   #  isinf(a) |
    dbinf = b .>= BIG

    sq1 = sqrt.(fx.^2 .+ da.^2)
    pval = fx .+ sq1 .+ da
    pval[dainf] = fx[dainf]

    sq2 = sqrt.(pval.^2 .+ db.^2)
    fxnew = pval .- sq2 .+ db

    fxnew[dbinf] = pval[dbinf]

    return fxnew
end


function smooth{T}(x::AbstractMatrix, a::AbstractMatrix, b::AbstractMatrix,
                   fx::AbstractMatrix, J::AbstractArray{T,3})

    BIG = 1e20

    da = a - x
    db = b - x

    dainf = a .<= -BIG   #  isinf(a) |
    dbinf = b .>= BIG

    sq1 = sqrt.(fx.^2 .+ da.^2)
    pval = fx .+ sq1 .+ da
    pval[dainf] = fx[dainf]

    sq2 = sqrt.(pval.^2 .+ db.^2)
    fxnew = pval .- sq2 .+ db

    fxnew[dbinf] = pval[dbinf]


    dpdy = 1.0 + fx./sq1
    dpdy[dainf] = 1.0
    dpdz = 1.0 + da./sq1
    dpdz[dainf] = 0.0
    dmdy = 1.0 - pval./sq2
    dmdy[dbinf] = 1.0
    dmdz = 1.0 - db./sq2
    dmdz[dbinf] = 0.0


    ff = dmdy .* dpdy
    xx = dmdy .* dpdz .+ dmdz

    Jac = copy(J)
    for j=1:size(Jac, 3)
        Jac[:, :, j] .*= ff
    end
    for i=1:size(Jac, 2)
        Jac[:, i, i] -= xx[:, i]
    end
    return fxnew, Jac
end

function serial_solver(f::Function, x0::Array{Float64,2}, a, b; maxit=10, verbose=false, n_bsteps=5, lam_bsteps=0.5)

    fun(u) = -f(u)
    smooth_me = true

    N = size(x0, 1)
    n_x = size(x0, 2)

    if size(a) != (N, n_x)
        a = fill(-Inf, N, n_x)
    end
    if size(b) != (N, n_x)
        b = fill(Inf, N, n_x)
    end

    tol = 1e-6
    eps = 1e-8

    err = 1
    it = 0

    n_bsteps = 5
    backsteps = lam_bsteps.^(0:(n_bsteps-1))

    x = x0
    res = fun(x0)
    if smooth_me
        res = smooth(x0, a, b, res)
    end
    err = maximum(abs, res)
    N = size(res, 1)
    err_0 = err
    if verbose
        println("Initial error: ", err_0)
    end

    while (err > tol) && (it < maxit)
        ii = 0
         # compute numerical gradient
        res = fun(x0)
        jac = zeros(N, n_x, n_x)
        for i = 1:n_x
            xx = copy(x0)
            xx[:, i] +=  eps
            jac[:, :, i] = (fun(xx) .- res)./eps
        end
        if smooth_me
            res, jac = smooth(x0, a, b, res, jac)
        end


        dx = zeros(size(x0))
        for n = 1:size(x0, 1)
            mat = jac[n, :, :]
            dx[n, :] = mat \ res[n, :]
        end

        for i in 1:n_bsteps
            lam = backsteps[i]
            x = x0 - lam*dx
            try
                res = fun(x)
                if smooth_me
                    res = smooth(x, a, b, res)
                end
                err = maximum(abs, res)
                ii = i
            catch
                err = Inf
            end
            if err<err_0
                break
            end
        end
        it = it + 1

        if verbose
            println("It: ", it, " ; Err: ", err, " ; nbsteps:",ii-1)
        end

        err_0 = err
        x0 = x

    end
    return x0, it

end
