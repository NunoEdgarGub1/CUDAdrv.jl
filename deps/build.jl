using Compat

using CUDAapi


## API routines

# these routines are the bare minimum we need from the API during build;
# keep in sync with the actual implementations in src/

macro apicall(libpath, fn, types, args...)
    quote
        lib = Libdl.dlopen($(esc(libpath)))
        sym = Libdl.dlsym(lib, $(esc(fn)))

        ccall(sym, Cint, $(esc(types)), $(map(esc, args)...))
    end
end

function version(libpath)
    ref = Ref{Cint}()
    status = @apicall(libpath, :cuDriverGetVersion, (Ptr{Cint}, ), ref)
    @assert status == 0
    return VersionNumber(ref[] ÷ 1000, mod(ref[], 100) ÷ 10)
end

function init(libpath, flags=0)
    @apicall(libpath, :cuInit, (Cint, ), flags)
end


## main

const config_path = joinpath(@__DIR__, "ext.jl")
const previous_config_path = config_path * ".bak"

function main()
    ispath(config_path) && mv(config_path, previous_config_path; remove_destination=true)
    config = Dict{Symbol,Any}()


    ## discover stuff

    driver_path = find_driver()
    config[:libcuda_path] = find_library(CUDAapi.libcuda, driver_path)
    config[:libcuda_vendor] = "NVIDIA"

    # initializing the library isn't necessary, but flushes out errors that otherwise would
    # happen during `version` or, worse, at package load time.
    status = init(config[:libcuda_path])
    if status != 0
        # decode some common errors (as we haven't loaded errors.jl yet)
        if status == -1
            error("Building against CUDA driver stubs, which is not supported.")
        elseif status == 100
            error("Initializing CUDA driver failed: no CUDA hardware available (code 100).")
        elseif status == 999
            error("Initializing CUDA driver failed: unknown error (code 999).")
        else
            error("Initializing CUDA driver failed with code $status.")
        end
    end

    config[:libcuda_version] = version(config[:libcuda_path])



    ## (re)generate ext.jl

    function globals(mod)
        all_names = names(mod, true)
        filter(name-> !any(name .== [module_name(mod), Symbol("#eval"), :eval]), all_names)
    end

    if isfile(previous_config_path)
        @debug("Checking validity of existing ext.jl...")
        @eval module Previous; include($previous_config_path); end
        previous_config = Dict{Symbol,Any}(name => getfield(Previous, name)
                                           for name in globals(Previous))

        if config == previous_config
            info("CUDAdrv.jl has already been built for this toolchain, no need to rebuild")
            mv(previous_config_path, config_path)
            return
        end
    end

    open(config_path, "w") do fh
        write(fh, "# autogenerated file with properties of the toolchain\n")
        for (key,val) in config
            write(fh, "const $key = $(repr(val))\n")
        end
    end

    # refresh the compile cache
    # NOTE: we need to do this manually, as the package will load & precompile after
    #       not having loaded a nonexistent ext.jl in the case of a failed build,
    #       causing it not to precompile after a subsequent successful build.
    if VERSION >= v"0.7.0-DEV.1735" ? Base.JLOptions().use_compiled_modules==1 :
                                      Base.JLOptions().use_compilecache==1
        Base.compilecache("CUDAdrv")
    end

    return
end

main()
