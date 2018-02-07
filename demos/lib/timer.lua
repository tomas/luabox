local signals = {}

local function resumeCoroutine( co, ... )
  local passed, err = coroutine.resume( co, ... )
  assert( passed, 'Timer error: ' .. tostring( err ) )
  return passed
end

local function wait(process, time_delta)
  local co = coroutine.running()
  local wakeUpTime = process.time + time_delta
  process.times[co] = wakeUpTime
  return coroutine.yield( co )
end

local function checkThreads( process )
  for co, wakeUpTime in pairs( process.times ) do
    if process.time > wakeUpTime then
      process.times[co] = nil
      resumeCoroutine( co )
    end
  end
end

local function waitSignal( name )
  local co = coroutine.running()
  if signals[name] then
    table.insert( signals[name], co )
  else
    signals[name] = { co }
  end
  return coroutine.yield( co )
end

local toResume = {} -- Prevent bugs caused by coroutines starting then pausing wrong thread
local function signal( name )
  for i, co in ipairs( signals[name] ) do
    if coroutine.status( co ) == 'suspended' then
      table.insert( toResume, co )
    end
  end
  signals[name] = nil
end

-- Wrapper function
local function newProcess( func )
  local process = {
    time = 0,
    times = {},
    update = function( self, dt )
      self.time = self.time + dt
      checkThreads( self )
      for _, co in ipairs( toResume ) do
        resumeCoroutine( co )
      end
      toResume = {}
    end,
  }

  setfenv(func,
    setmetatable( {
      waitSignal = waitSignal,
      signal = signal,
      wait = function( seconds )
        process.time = 0
        return wait( process, seconds )
      end,
    }, {
      __index = getfenv( 0 ),
    })
  )

  local co = coroutine.create(func)
  resumeCoroutine(co, process)

  return process
end

local ffi = require("ffi")
local math_floor = math.floor

ffi.cdef [[
  typedef long time_t;
  typedef int clockid_t;

  typedef struct tspec {
      time_t   tv_sec;        /* seconds */
      long     tv_nsec;       /* nanoseconds */
  } nanotime;

  int clock_gettime(clockid_t clk_id, struct tspec *tp);
]]

local pnano = assert(ffi.new("nanotime[?]", 1))
local gettime = ffi.C.clock_gettime

local function now()
  gettime(1, pnano)
  return tonumber(pnano[0].tv_sec * 1000 + math_floor(tonumber(pnano[0].tv_nsec/1000000)))
end

return {
  new = newProcess,
  wait = wait,
  now = now
}