# Where.jl

Locally open source code locations of function methods inside Julia.

## Installation
```
julia> ]
pkg> add https://github.com/sisl/Where.jl.git
```

## Example Usage

```
julia> import StatsBase: sample, Weights
julia> a = [1, 3, 5, 7]
julia> w = [2, 4, 6, 8]

julia> sample(a, Weights(w))          # call the function with a specific method.
7

julia> @which sample(a, Weights(w))   # (built-in) output the src location and line number.
sample(a::AbstractArray, wv::StatsBase.AbstractWeights) in StatsBase at ~/.julia/packages/StatsBase/ZxhK8/src/sampling.jl:513

julia> using Where
julia> @where sample(a, Weights(w))   # (this pkg) open the src file at the call line number, using gedit.
```
The last line above spawns a new tab in `gedit` where the cursor automatically lands at the correct line number, Line 513 in this example.
![alt text](pics/gedit_ss.png)


## TODO
- Uses `gedit` by default. Parametrize this, and add support for other OS and editors.
- Open the external text editor to be a background process (such that the Julia terminal isn't blocked out as it is now).