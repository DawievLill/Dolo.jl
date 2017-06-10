@compat abstract type Grid end

function Base.show(io::IO, grid::Grid)
    println(typeof(grid))
end

function mlinspace(min, max, n)
    nodes = map(linspace, min, max, n)
    return QE.gridmake(nodes...)
end

immutable EmptyGrid <: Grid
    # this grid does not exist ;-)
end

nodes(grid::EmptyGrid) = nothing
n_nodes(grid::EmptyGrid) = 0
node(grid::EmptyGrid, i::Int) = nothing # fail if i!=1 ?


immutable PointGrid <: Grid
    point::Vector{Float64}
end
nodes(grid::PointGrid) = grid.point'
n_nodes(grid::PointGrid) = 1
node(grid::PointGrid, i::Int) = point # fail if i!=1 ?


immutable UnstructuredGrid <: Grid
    nodes::Matrix{Float64}
end
nodes(grid::UnstructuredGrid) = grid.nodes
n_nodes(grid::UnstructuredGrid) = size(grid.nodes, 1)
node(grid::UnstructuredGrid, i::Int) = grid.nodes[i, :]


immutable CartesianGrid <: Grid
    min::Vector{Float64}
    max::Vector{Float64}
    n::Vector{Int}
    nodes::Matrix{Float64}
    function CartesianGrid(min, max, n)
        nodes = mlinspace(min, max, n)
        return new(min, max, n, nodes)
    end
end
nodes(grid::Grid) = grid.nodes
n_nodes(grid::Grid) = size(grid.nodes, 1)
node(grid::Grid, i::Int) = grid.nodes[i, :]

immutable SmolyakGrid <: Grid

    min::Vector{Float64}
    max::Vector{Float64}
    mu::Vector{Int}
    nodes::Matrix{Float64}

    function SmolyakGrid(min::Array{Float64,1}, max::Array{Float64,1}, mu::Int64)
        return new(min, max, [mu for i=1:length(min)])
    end

    function SmolyakGrid(min::Array{Float64,1}, max::Array{Float64,1}, mu::Array{Int64,1})
        nodes = zeros(10, 10) # TODO !!!!
        return new(min, max, mu, nodes)
    end

end
