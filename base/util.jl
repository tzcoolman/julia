# timing

# system date in seconds
time() = ccall(:clock_now, Float64, ())

# high-resolution relative time, in nanoseconds
time_ns() = ccall(:jl_hrtime, Uint64, ())

function tic()
    t0 = time_ns()
    task_local_storage(:TIMERS, (t0, get(task_local_storage(), :TIMERS, ())))
    return t0
end

function toq()
    t1 = time_ns()
    timers = get(task_local_storage(), :TIMERS, ())
    if is(timers,())
        error("toc() without tic()")
    end
    t0 = timers[1]
    task_local_storage(:TIMERS, timers[2])
    (t1-t0)/1e9
end

function toc()
    t = toq()
    println("elapsed time: ", t, " seconds")
    return t
end

# print elapsed time, return expression value
macro time(ex)
    quote
        local t0 = time_ns()
        local val = $(esc(ex))
        local t1 = time_ns()
        println("elapsed time: ", (t1-t0)/1e9, " seconds")
        val
    end
end

# print nothing, return elapsed time
macro elapsed(ex)
    quote
        local t0 = time_ns()
        local val = $(esc(ex))
        (time_ns()-t0)/1e9
    end
end

# print nothing, return value & elapsed time
macro timed(ex)
    quote
        local t0 = time_ns()
        local val = $(esc(ex))
        val, (time_ns()-t0)/1e9
    end
end

function peakflops(n=2000)
    a = rand(n,n)
    t = @elapsed a*a
    t = @elapsed a*a
    floprate = (2.0*float64(n)^3/t)
    println("The peak flop rate is ", floprate*1e-9, " gigaflops")
    floprate
end

# searching definitions

function whicht(f, types)
    for m = methods(f, types)
        if isa(m[3],LambdaStaticData)
            lsd = m[3]::LambdaStaticData
            d = f.env.defs
            while !is(d,())
                if is(d.func.code, lsd)
                    print(OUTPUT_STREAM, f.env.name)
                    show(OUTPUT_STREAM, d); println(OUTPUT_STREAM)
                    return
                end
                d = d.next
            end
        end
    end
end

which(f, args...) = whicht(f, map(a->(isa(a,Type) ? Type{a} : typeof(a)), args))

macro which(ex)
    ex = expand(ex)
    exret = Expr(:call, :error, "expression is not a function call")
    if !isa(ex, Expr)
        # do nothing -> error
    elseif ex.head == :call
        exret = Expr(:call, :which, map(esc, ex.args)...)
    elseif ex.head == :body
        a1 = ex.args[1]
        if isa(a1, Expr) && a1.head == :call
            a11 = a1.args[1]
            if a11 == :setindex!
                exret = Expr(:call, :which, a11, map(esc, a1.args[2:end])...)
            end
        end
    elseif ex.head == :thunk
        exret = Expr(:call, :error, "expression is not a function call, or is too complex for @which to analyze; "
                                  * "break it down to simpler parts if possible")
    end
    exret
end

# source files, editing

function find_source_file(file)
    if file[1]!='/' && !is_file_readable(file)
        file2 = find_in_path(file)
        if is_file_readable(file2)
            return file2
        else
            file2 = "$JULIA_HOME/../share/julia/base/$file"
            if is_file_readable(file2)
                return file2
            end
        end
    end
    return file
end

function edit(file::String, line::Integer)
    if OS_NAME == :Windows || OS_NAME == :Darwin
        default_editor = "open"
    elseif isreadable("/etc/alternatives/editor")
        default_editor = "/etc/alternatives/editor"
    else
        default_editor = "emacs"
    end
    envvar = haskey(ENV,"JULIA_EDITOR") ? "JULIA_EDITOR" : "EDITOR"
    editor = get(ENV, envvar, default_editor)
    issrc = length(file)>2 && file[end-2:end] == ".jl"
    if issrc
        file = find_source_file(file)
    end
    if editor == "emacs"
        if issrc
            jmode = "$JULIA_HOME/../../contrib/julia-mode.el"
            run(`emacs $file --eval "(progn
                                     (require 'julia-mode \"$jmode\")
                                     (julia-mode)
                                     (goto-line $line))"`)
        else
            run(`emacs $file --eval "(goto-line $line)"`)
        end
    elseif editor == "vim"
        run(`vim $file +$line`)
    elseif editor == "textmate" || editor == "mate"
        spawn(`mate $file -l $line`)
    elseif editor == "subl"
        spawn(`subl $file:$line`)
    elseif OS_NAME == :Windows && (editor == "start" || editor == "open")
        spawn(`start /b $file`)
    elseif OS_NAME == :Darwin && (editor == "start" || editor == "open")
        spawn(`open -t $file`)
    elseif editor == "kate"
        spawn(`kate $file -l $line`)
    else
        run(`$(shell_split(editor)) $file`)
    end
    nothing
end
edit(file::String) = edit(file, 1)

function less(file::String, line::Integer)
    pager = get(ENV, "PAGER", "less")
    run(`$pager +$(line)g $file`)
end
less(file::String) = less(file, 1)

edit(f::Function)    = edit(functionloc(f)...)
edit(f::Function, t) = edit(functionloc(f,t)...)
less(f::Function)    = less(functionloc(f)...)
less(f::Function, t) = less(functionloc(f,t)...)

# print a warning only once

const have_warned = (ByteString=>Bool)[]
function warn_once(msg::String...; depth=0)
    msg = bytestring(msg...)
    haskey(have_warned,msg) && return
    have_warned[msg] = true
    warn(msg; depth=depth+1)
end

# blas utility routines
blas_is_openblas() =
    try
        cglobal((:openblas_set_num_threads, Base.libblas_name), Void)
        true
    catch
        false
    end

openblas_get_config() = chop(bytestring( ccall((:openblas_get_config, Base.libblas_name), Ptr{Uint8}, () )))

function blas_set_num_threads(n::Integer)
    if blas_is_openblas()
        return ccall((:openblas_set_num_threads, Base.libblas_name), Void, (Int32,), n)
    end

    # MKL may let us set the number of threads in several ways
    set_num_threads = try
        cglobal((:MKL_Set_Num_Threads, Base.libblas_name), Void)
    catch
        C_NULL
    end
    if set_num_threads != C_NULL
        return ccall(set_num_threads, Void, (Cint,), n)
    end

    # OSX BLAS looks at an environment variable
    @osx_only ENV["VECLIB_MAXIMUM_THREADS"] = n

    return nothing
end

function check_blas()
    if blas_is_openblas()
        openblas_config = openblas_get_config()
        openblas64 = ismatch(r".*USE64BITINT.*", openblas_config)
    else
        openblas64 = false
    end
    if Base.USE_BLAS64 != openblas64
        if !openblas64
            println("ERROR: OpenBLAS was not built with 64bit integer support.")
            println("You're seeing this error because Julia was built with USE_BLAS64=1")
            println("Please rebuild Julia with USE_BLAS64=0")
        else
            println("ERROR: Julia was not built with support for OpenBLAS with 64bit integer support")
            println("You're seeing this error because Julia was built with USE_BLAS64=0")
            println("Please rebuild Julia with USE_BLAS64=1")
        end
        println("Quitting.")
        quit()
    end
end

# system information

function versioninfo(io::IO=OUTPUT_STREAM, verbose::Bool=false)
    println(io,             "Julia $version_string")
    println(io,             commit_string)
    println(io,             "Platform Info:")
    println(io,             "  System: ", Sys.OS_NAME, " (", Sys.MACHINE, ")")
    println(io,             "  WORD_SIZE: ", Sys.WORD_SIZE)
    if verbose
        lsb = readchomp(ignorestatus(`lsb_release -ds`) .> SpawnNullStream())
        if lsb != ""
            println(io,     "           ", lsb)
        end
        println(io,         "  uname: ",readchomp(`uname -mprsv`))
        println(io,         "Memory: $(Sys.total_memory()/2^30) GB ($(Sys.free_memory()/2^20) MB free)")
        try println(io,     "Uptime: $(Sys.uptime()) sec") catch end
        print(io,           "Load Avg: ")
        print_matrix(io,    Sys.loadavg()')
        println(io          )
        println(io,         Sys.cpu_info())
    end
    if Base.libblas_name == "libopenblas"
        openblas_config = openblas_get_config()
        println(io,         "  BLAS: ",libblas_name, " (", openblas_config, ")")
    else
        println(io,         "  BLAS: ",libblas_name)
    end
    println(io,             "  LAPACK: ",liblapack_name)
    println(io,             "  LIBM: ",libm_name)
    if verbose
        println(io,         "Environment:")
        for (k,v) in ENV
            if !is(match(r"JULIA|PATH|FLAG|^TERM$|HOME",k), nothing)
                println(io, "  $(k) = $(v)")
            end
        end
        println(io          )
        println(io,         "Package Directory: ", Pkg.dir())
        println(io,         "Packages Installed:")
        Pkg.status(io       )
    end
end

# `methodswith` -- shows a list of methods using the type given

function methodswith(io::IO, t::Type, m::Module, showparents::Bool)
    for nm in names(m)
        try
           mt = eval(nm)
           d = mt.env.defs
           while !is(d,())
               if any(map(x -> x == t || (showparents && t <: x && x != Any && x != ANY && !isa(x, TypeVar)), d.sig))
                   print(io, nm)
                   show(io, d)
                   println(io)
               end
               d = d.next
           end
        end
    end
end

methodswith(t::Type, m::Module, showparents::Bool) = methodswith(OUTPUT_STREAM, t, m, showparents)
methodswith(t::Type, showparents::Bool) = methodswith(OUTPUT_STREAM, t, showparents)
methodswith(t::Type, m::Module) = methodswith(OUTPUT_STREAM, t, m, false)
methodswith(t::Type) = methodswith(OUTPUT_STREAM, t, false)
function methodswith(io::IO, t::Type, showparents::Bool)
    mainmod = current_module()
    # find modules in Main
    for nm in names(mainmod)
        if isdefined(mainmod,nm)
            mod = eval(mainmod, nm)
            if isa(mod, Module)
                methodswith(io, t, mod, showparents)
            end
        end
    end
end

# Conditional usage of packages and modules
usingmodule(name::Symbol) = eval(current_module(), Expr(:toplevel, Expr(:using, name)))
usingmodule(name::String) = usingmodule(symbol(name))
