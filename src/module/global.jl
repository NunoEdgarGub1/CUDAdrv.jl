# Module-scope global variables

export
    CuGlobal, get, set

# forward definition
type Buffer
    ptr::Ptr{Void}
    bytesize::Int

    ctx::CuContext
end


"""
    CuGlobal{T}(mod::CuModule, name::String)

Acquires a typed global variable handle from a named global in a module.
"""
immutable CuGlobal{T}
    buf::Buffer

    function (::Type{CuGlobal{T}}){T}(mod::CuModule, name::String)
        ptr_ref = Ref{Ptr{Void}}()
        nbytes_ref = Ref{Cssize_t}()
        @apicall(:cuModuleGetGlobal, (Ptr{Ptr{Void}}, Ptr{Cssize_t}, CuModule_t, Ptr{Cchar}), 
                                     ptr_ref, nbytes_ref, mod, name)
        if nbytes_ref[] != sizeof(T)
            throw(ArgumentError("size of global '$name' does not match type parameter type $T"))
        end
        buf = Buffer(ptr_ref[], nbytes_ref[], CuCurrentContext())

        return new{T}(buf)
    end
end

Base.cconvert(::Type{Ptr{Void}}, var::CuGlobal) = var.buf

Base.:(==)(a::CuGlobal, b::CuGlobal) = a.handle == b.handle
Base.hash(var::CuGlobal, h::UInt) = hash(var.ptr, h)

"""
    eltype(var::CuGlobal)

Return the element type of a global variable object.
"""
Base.eltype{T}(::Type{CuGlobal{T}}) = T

"""
    get(var::CuGlobal)

Return the current value of a global variable.
"""
function Base.get{T}(var::CuGlobal{T})
    val_ref = Ref{T}()
    @apicall(:cuMemcpyDtoH, (Ptr{Void}, Ptr{Void}, Csize_t),
                            val_ref, var.buf, var.buf.bytesize)
    return val_ref[]
end

"""
    set(var::CuGlobal{T}, T)

Set the value of a global variable to `val`
"""
function set{T}(var::CuGlobal{T}, val::T)
    val_ref = Ref{T}(val)
    @apicall(:cuMemcpyHtoD, (Ptr{Void}, Ptr{Void}, Csize_t),
                            var.buf, val_ref, var.buf.bytesize)
end
