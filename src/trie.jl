mutable struct Trie{K,V}
    value::V
    children::Dict{K,Trie{K,V}}
    is_key::Bool

    function Trie{K,V}() where {K,V}
        self = new{K,V}()
        self.children = Dict{K,Trie{K,V}}()
        self.is_key = false
        return self
    end
end

function Base.empty!(t::Trie)
    empty!(t.children)
    t.is_key = false 
    return nothing
end

_prefix(::Trie{K, V}) where {K, V} = K[]

function Base.setindex!(t::Trie{K,V}, val, key) where {K, V}
    node = t
    for subkey in key
        if !haskey(node.children, subkey)
            node.children[subkey] = Trie{K,V}()
        end
        node = node.children[subkey]
    end
    node.is_key = true
    node.value = val
end

function subtrie(t::Trie, prefix)
    node = t
    for subkey in prefix
        if !haskey(node.children, subkey)
            return nothing
        else
            node = node.children[subkey]
        end
    end
    return node
end

function subtry(t::Trie, prefix)
    node = t 
    last_key_node = t 
    for subkey in prefix 
        if !haskey(node.children, subkey)
            return last_key_node 
        else
            node = node.children[subkey]
        end
        if node.is_key
            last_key_node = node 
        end
    end
    return node.is_key ? node : last_key_node
end

function Base.getindex(t::Trie, key)
    node = subtrie(t, key)
    if !isnothing(node) && node.is_key 
        return node.value 
    else
        throw(KeyError("key not found: $key"))
    end
end

function Base.haskey(t::Trie, key)
    node = subtrie(t, key)
    !isnothing(node) && node.is_key
end

function _keys!(t::Trie, prefix=_prefix(t), found_keys=Vector{typeof(prefix)}(); max_depth::Int=typemax(Int))
    if t.is_key
        push!(found_keys, prefix)
    end
    max_depth ≤ 0 && return found_keys
    for (subkey, child) in t.children
        _keys!(child, vcat(prefix, subkey), found_keys; max_depth=max_depth-1)
    end
    return found_keys
end
function _keys(t::Trie, prefix=_prefix(t); max_depth::Int=typemax(Int))
    found_keys = Vector{typeof(prefix)}()
    return _keys!(t, prefix, found_keys; max_depth)
end

Base.keys(t::Trie) = _keys(t)
Base.isempty(t::Trie) = isempty(keys(t))

function keys_with_prefix(t::Trie, prefix; max_depth::Int=typemax(Int))
    st = subtrie(t, prefix)
    output = Vector{typeof(prefix)}()
    if !isnothing(st)
        _keys!(st, prefix, output; max_depth)
    end
    return output
end
