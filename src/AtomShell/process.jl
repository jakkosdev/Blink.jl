using Lazy, JSON, MacroTools

hascommand(c) =
  try read(`which $c`, String); true catch e false end

run_rdr(cmd; kw...) = run(cmd, Base.spawn_opts_inherit()...; kw...)

"""
  resolve_blink_asset(path...)

Find a file, expressed as a relative path from the Blink package
folder. Example:

  resolve_blink_asset("src", "Blink.jl") -> /home/<user>/.julia/v0.6/Blink/src/Blink.jl
"""

resolve_blink_asset(path...) = joinpath(folder_path, path...)



@deprecate resolve(pkg, path...) resolve_blink_asset(path...)

# node-inspector

_inspector = nothing

function inspector()
  if hascommand("node-inspector")
    global _inspector
    _inspector != nothing && process_running(_inspector) && return _inspector
    _inspector = spawn_rdr(`node-inspector`)
  end
end

function inspector(port)
  inspector()
  inspector_cmd = `http://localhost:8080/debug'?'port=$port`
  if Sys.isapple()
    return run(`open $inspector_cmd`)
  elseif Sys.islinux()
    return run(`xdg-open $inspector_cmd`)
  elseif Sys.iswindows()
    return run(`cmd /C start $inspector_cmd`)
  end
  error("Cannot open inspector (unknown operating system).")
end

# atom-shell

import Base: Process

export Electron

mutable struct Electron <: Shell
  proc::Process
  sock::TCPSocket
  handlers::Dict{String, Any}
end

Electron(proc, sock) = Electron(proc, sock, Dict())

@static if Sys.isapple()
  _electron() = resolve_blink_asset("deps/Julia.app/Contents/MacOS/Julia")
elseif Sys.islinux()
  _electron() = resolve_blink_asset("deps/atom/electron")
elseif Sys.iswindows()
  _electron() = resolve_blink_asset("deps", "atom", "electron.exe")
end
mainjs() = resolve_blink_asset("src", "AtomShell", "main.js")

function electron()
  # path = get(ENV, "ELECTRON_PATH", _electron)
  path = _electron()
  isfile(path) || error("Cannot find Electron. Try `Blink.AtomShell.install()`.")
  return path
end

port() = rand(2_000:10_000)

function try_connect(args...; interval = 0.01, attempts = 500)
  for i = 1:attempts
    try
      return connect(args...)
    catch e
      i == attempts && rethrow()
    end
    sleep(interval)
  end
end

function init(; debug = false)
  electron() # Check path exists
  p, dp = port(), port()
  debug && inspector(dp)
  dbg = debug ? "--debug=$dp" : []
  proc = (debug ? run_rdr : run)(`$(electron()) $dbg $(mainjs()) port $p`; wait=false)
  conn = try_connect(ip"127.0.0.1", p)
  shell = Electron(proc, conn)
  initcbs(shell)
  return shell
end

# JS Communication

import ..Blink: msg, enable_callbacks!, handlers, handle_message, active

msg(shell::Electron, m) = (JSON.print(shell.sock, m); println(shell.sock))

handlers(shell::Electron) = shell.handlers

function initcbs(shell)
  enable_callbacks!(shell)
  @async begin
    while active(shell)
      @errs handle_message(shell, JSON.parse(shell.sock))
    end
  end
end

# utils

export active

Base.close(shell::Electron) = close(shell.sock)
Base.isopen(shell::Electron) = process_running(shell.proc)

# TODO: Deprecate these functions in favor of methods above.
active(shell::Electron) = isopen(shell)
quit(shell::Electron) = close(shell)

# Keep track of the active electron process (see the `shell` function).
const _active_electron_process = Ref{Union{Electron, Nothing}}(nothing)

"""
    shell(; debug=false)

Get the currently active [`Electron`](@ref) shell instance (or activate one if
none exists yet).

NOTE: The `debug` keyword argument only takes effect if there is not an active
`Electron` instance. If there *is* an active instance, this function returns
that instance without regards to whether or not the `debug` flag matches.
"""
function shell(; debug=false)::Electron
    # TODO: It might make sense to track whether or not the shell was started
    # with the debug flag and issue a warning if the user requested debug and
    # the active shell is non-debug.
    proc = _active_electron_process[]
    if proc !== nothing && active(proc)
        return proc
    end

    proc = init(debug=debug)
    _active_electron_process[] = proc
    return proc
end
