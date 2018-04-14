using DataFrames
using StatsBase
include("dist.jl")

type kMeansResults
    x::DataFrames.DataFrame
    k::Int
    estimatedClass::Array{Int}
    iterCount::Int
    costArray::Array{Float64}
end

function kMeans(data::DataFrame, k::Int)

    # initialize
    dataPointsNum = size(data, 1)
    estimatedClass = Array{Int}(dataPointsNum)
    sample!(1:k, estimatedClass)

    iterCount = 0
    costArray = Float64[]
    while true

        # update
        representativePoints = updateRepresentative(data, estimatedClass, k)
        tempEstimatedClass, cost = updateGroupBelonging(data, dataPointsNum, representativePoints, k)

        push!(costArray, cost)

        if estimatedClass == tempEstimatedClass
            iterCount += 1
            break
        end
        estimatedClass = tempEstimatedClass
        iterCount += 1
    end
    return kMeansResults(data, k, estimatedClass, iterCount, costArray)
end

function updateRepresentative(data::DataFrame, estimatedClass::Array{Int}, k::Int)
    representativePoints = Array{Array{Float64,1}}(k)
    for representativeIndex in 1:k
        groupIndex = find(estimatedClass .== representativeIndex)
        groupData = data[groupIndex, :]

        representativePoint = [ valArray[1] for valArray in colwise(mean, groupData) ]
        representativePoints[representativeIndex] = representativePoint
    end
    return representativePoints
end

function updateGroupBelonging(data::DataFrame, dataPointsNum::Int, representativePoints::Array{Array{Float64, 1}}, k::Int)
    tempEstimatedClass = Array{Int}(dataPointsNum)

    cost = 0.0
    for dataIndex in 1:dataPointsNum
        dataPoint = Array(data[dataIndex, :])
        distances = Array{Float64}(k)
        for representativeIndex in 1:k
            distances[representativeIndex] = calcDist(dataPoint, representativePoints[representativeIndex])
        end

        # TODO: check the existence of argmin
        # TODO: this cost calculation is bad hack
        classIndex = sortperm(distances)[1]
        tempEstimatedClass[dataIndex] = classIndex
        cost += distances[classIndex] ^ 2
    end
    return tempEstimatedClass, cost
end

function calcDist(sourcePoint::Array, destPoint::Array; method="euclidean")

    if method == "euclidean"
        return euclidean(sourcePoint, destPoint)
    elseif method == "minkowski"
        return minkowski(sourcePoint, destPoint)
    end
end
