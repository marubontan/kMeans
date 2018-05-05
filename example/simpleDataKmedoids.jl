using DataFrames
using Distributions
import Distances
include("../src/kmedoids.jl")

function makeData()
    groupOne = rand(MvNormal([10.0, 10.0], 5.0 * eye(2)), 100)
    groupTwo = rand(MvNormal([0.0, 0.0], 10 * eye(2)), 100)
    return hcat(groupOne, groupTwo)'
end

function main()
    data = makeData()'

    k = 2
    distanceMatrix = Distances.pairwise(Distances.SqEuclidean(), data)

    results = kMedoids(distanceMatrix, k)
    print(results)
end

main()