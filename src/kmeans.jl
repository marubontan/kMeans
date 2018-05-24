using DataFrames
using StatsBase
include("type.jl")
include("predict.jl")
include("dist.jl")
include("utils.jl")


struct KMeansResults <: ClusteringResult
    x::DataFrames.DataFrame
    k::Int
    estimatedClass::Array{Int}
    centroids::Array{Array}
    iterCount::Int
    costArray::Array{Float64}
end


"""
    kMeans(data, k)

Do clustering to data with K-means algorithm.

# Arguments
- `data::DataFrame`: the clustering target data.
- `k::Int`: the number of clusters.

# Examples
```julia-kMeans
julia> kMeans(DataFrame(x = [1,2,3], y = [4,5,6]),2)
KMeansResults(3×2 DataFrames.DataFrame
│ Row │ x │ y │
├─────┼───┼───┤
│ 1   │ 1 │ 4 │
│ 2   │ 2 │ 5 │
│ 3   │ 3 │ 6 │, 2, [1, 1, 1], 1, [4.0])
```
"""
function kMeans(data::DataFrame, k::Int; initializer=nothing)

    # initialize
    dataPointsNum = size(data, 1)
    estimatedClass = assignRandomKClass(dataPointsNum, k)
    if initializer == "kmeans++"
        centroids = kMeansPlusPlus(data, k)
    else
        centroids = updateCentroids(data, estimatedClass, k)
    end

    iterCount = 0
    centroidsArray = []
    costArray = Float64[]
    while true

        # update
        tempEstimatedClass, cost, nearestDist = updateGroupBelonging(data,
                                                                     dataPointsNum,
                                                                     centroids,
                                                                     k)

        push!(costArray, cost)

        centroids = updateCentroids(data, tempEstimatedClass, k)

        if length(Set(tempEstimatedClass)) < k
            centroids = assignDataOnEmptyCluster(data,
                                                 tempEstimatedClass,
                                                 centroids,
                                                 nearestDist)
        end

        push!(centroidsArray, centroids)

        if judgeConvergence(estimatedClass, tempEstimatedClass)
            iterCount += 1
            break
        end

        estimatedClass = tempEstimatedClass
        iterCount += 1
    end
    return KMeansResults(data,
                         k,
                         estimatedClass,
                         centroidsArray,
                         iterCount,
                         costArray)
end


function assignRandomKClass(dataPointsNum::Int, k::Int)
    estimatedClass = Array{Int}(dataPointsNum)
    sample!(1:k, estimatedClass)
    return estimatedClass
end


function updateCentroids(data::DataFrame,
                         estimatedClass::Array{Int},
                         k::Int)

    centroids = Array{Array{Float64,1}}(k)
    for centroidIndex in 1:k
        groupIndex = find(estimatedClass .== centroidIndex)
        groupData = data[groupIndex, :]

        centroid = [ valArray[1] for valArray in colwise(mean, groupData) ]
        centroids[centroidIndex] = centroid
    end
    return centroids
end


function updateGroupBelonging(data::DataFrame,
                              dataPointsNum::Int,
                              centroids::Array,
                              k::Int)

    tempEstimatedClass = Array{Int}(dataPointsNum)

    cost = 0.0
    distanceBetweenDataPointAndNearestCentroid = Array{Float64}(dataPointsNum)
    for dataIndex in 1:dataPointsNum
        dataPoint = Array(data[dataIndex, :])
        distances = Array{Float64}(k)
        for centroidIndex in 1:k
            distances[centroidIndex] = calcDist(dataPoint, centroids[centroidIndex])
        end

        distanceBetweenDataPointAndNearestCentroid[dataIndex] = minimum(distances)
        classIndex = indmin(distances)
        tempEstimatedClass[dataIndex] = classIndex

        # TODO: this cost calculation is bad hack
        cost += distances[classIndex] ^ 2
    end
    return tempEstimatedClass, cost, distanceBetweenDataPointAndNearestCentroid
end


function assignDataOnEmptyCluster(data::DataFrame,
                                  label::Array{Int},
                                  centers::Array{Array{Float64, 1}, 1},
                                  nearestDist::Array{Float64, 1})

    emptyCluster = findEmptyCluster(label, centers)
    nearestDistProb = makeValuesProbabilistic(nearestDist)
    pickedDataPointsIndex = sample(Array(1:nrow(data)),
                                   Weights(nearestDistProb),
                                   length(emptyCluster);
                                   replace=false)

    for (i,cluster) in enumerate(emptyCluster)
        centers[cluster] = vec(Array(data[pickedDataPointsIndex[i], :]))
    end
    return centers
end


function findEmptyCluster(label::Array{Int}, centers::Array)

    emptyCluster = collect(setdiff(Set(1:length(centers)), Set(label)))
    return emptyCluster
end


function kMeansPlusPlus(data::DataFrame, k::Int)

    dataDict = dataFrameToDict(data)
    ind = randomlyChooseOneDataPoint(dataDict)
    distanceDict = calcDistBetweenCenterAndDataPoints(dataDict, ind)

    distanceProbDict = makeDictValueProbabilistic(distanceDict)

    centroidsIndices = Array{Int}(k)
    centroidsIndices[1] = ind
    for i in 2:k
        centroidsIndex = wrapperToStochasticallyPickUp(distanceProbDict, 1)[1]
        centroidsIndices[i] = centroidsIndex

        if i == k
            break
        end

        distanceDict = updateDistanceDict(distanceDict, dataDict, centroidsIndex)

        distanceProbDict = makeDictValueProbabilistic(distanceDict)
    end

    centroids = dataFrame2JaggedArray(data[centroidsIndices, :])
    return centroids
end


function randomlyChooseOneDataPoint(data::Dict{Int, Array{Float64, 1}})
    randomIndex = rand([k for k in keys(data)], 1)[1]
    return randomIndex
end


function wrapperToStochasticallyPickUp(data::Dict{Int, Float64},
                                       n::Int)

    len = length(keys(data))

    index = Array{Int}(len)
    probs = Array{Float64}(len)
    for (i, pair) in enumerate(data)
        index[i] = pair[1]
        probs[i] = pair[2]
    end

    return sample(index, Weights(probs), n; replace=false)
end


function updateDistanceDict(distanceDict::Dict{Int, Float64},
                            dataDict::Dict{Int, Array{Float64, 1}},
                            ind::Int)

    distanceBetweenNewCentroidAndDataPoints = calcDistBetweenCenterAndDataPoints(dataDict, ind)
    for pair in distanceDict
        if pair[2] > distanceBetweenNewCentroidAndDataPoints[pair[1]]
            distanceDict[pair[1]] = distanceBetweenNewCentroidAndDataPoints[pair[1]]
        end
    end
    return distanceDict
end

function _predict(result::KMeansResults, target::DataFrame)
    centroids = result.centroids[end]

    row,col = size(target)

    predicted = Array{Int}(row)
    for dataPointIndex in 1:row

        distance = Array{Float64}(col)
        for (cluster,centroid) in enumerate(centroids)
            distance[cluster] = calcDist(Array(target[dataPointIndex, :]), centroid)
        end

        predicted[dataPointIndex] = indmin(distance)
    end
    return predicted
end
