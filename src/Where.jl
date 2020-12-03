"""
Locally open locations of function calls in the source code
"""
module Where

import Base: typesof, insert!

include("main.jl")
export
    where,
    @where

end  # module