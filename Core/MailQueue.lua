-- Mailroom / MailQueue.lua
-- Throttled queue for mail open and collect operations.
-- Handles all TakeInboxItem and TakeInboxMoney calls with server-safe
-- delays to prevent silent operation failures.
--
-- The WoW mail server silently drops operations that fire faster than
-- ~100ms apart. This queue ensures every mail action (take item, take
-- money, delete) executes sequentially with a configurable delay between
-- each operation. Without this, bulk mail collection silently fails on
-- random items with no error or feedback to the player.

local AddonName, MR = ...

-------------------------------------------------------------------------------
-- Queue Module
-------------------------------------------------------------------------------

MR.Queue = {}

-------------------------------------------------------------------------------
-- Queue State
-------------------------------------------------------------------------------

local queue        = {}   -- list of pending operation closures
local queueRunning = false -- true while the queue is actively processing
local isPaused     = false -- true when the user has manually paused

-- Callbacks that other modules can set to react to queue state changes.
-- MailFrame uses these to update button text and progress indicators.
MR.Queue.onStart    = nil  -- called when queue begins processing
MR.Queue.onStop     = nil  -- called when queue finishes or is cleared
MR.Queue.onProgress = nil  -- called after each op with (remaining, total)

-- Tracks the total number of operations added in the current batch,
-- used to calculate progress percentage.
local totalOps = 0

-------------------------------------------------------------------------------
-- Internal Processing
-------------------------------------------------------------------------------

-- Processes the next operation in the queue.
-- Pops the first closure, executes it, then schedules itself again via
-- C_Timer.After using the player's configured throttle delay. When the
-- queue empties, resets state and fires the onStop callback.
local function ProcessQueue()
    if isPaused then
        return
    end

    if #queue == 0 then
        queueRunning = false
        totalOps = 0
        if MR.Queue.onStop then
            MR.Queue.onStop()
        end
        return
    end

    local op = table.remove(queue, 1)

    -- Execute the operation in a protected call so one bad mail item
    -- doesn't kill the entire queue. Errors are printed to chat.
    local ok, err = pcall(op)
    if not ok then
        MR.Addon:Print("Queue error: " .. tostring(err))
    end

    if MR.Queue.onProgress then
        MR.Queue.onProgress(#queue, totalOps)
    end

    local delay = MR.Addon.db and MR.Addon.db.profile.throttleDelay or 0.15
    C_Timer.After(delay, ProcessQueue)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Adds a mail operation to the throttle queue.
-- @param op (function) The operation to execute. Should be a zero-arg
--           closure that captures any needed index or mail ID values at
--           queue time, not at execution time. This is critical because
--           TakeInboxItem indices are 1-based and shift downward as items
--           are removed — by the time a queued op executes, the original
--           index may point to a different mail item.
-- @param priority (boolean) If true, inserts at the front of the queue
--                 instead of the back. Used for urgent operations like
--                 COD acceptance prompts.
function MR.Queue.Add(op, priority)
    if priority then
        table.insert(queue, 1, op)
    else
        table.insert(queue, op)
    end
    totalOps = totalOps + 1

    if not queueRunning and not isPaused then
        queueRunning = true
        if MR.Queue.onStart then
            MR.Queue.onStart()
        end
        ProcessQueue()
    end
end

-- Clears all pending operations and resets the queue.
-- Does not cancel an operation that is currently mid-execution (the
-- current C_Timer.After callback will fire but find an empty queue).
function MR.Queue.Clear()
    wipe(queue)
    queueRunning = false
    isPaused = false
    totalOps = 0
    if MR.Queue.onStop then
        MR.Queue.onStop()
    end
end

-- Pauses queue processing. The current in-flight timer will fire but
-- ProcessQueue will return immediately without executing the next op.
-- Call Resume() to continue from where it left off.
function MR.Queue.Pause()
    isPaused = true
end

-- Resumes a paused queue. Restarts processing from the next pending op.
function MR.Queue.Resume()
    if isPaused then
        isPaused = false
        if #queue > 0 and not queueRunning then
            queueRunning = true
            ProcessQueue()
        end
    end
end

-- Returns the number of operations remaining in the queue.
-- @return (number) Count of pending operations.
function MR.Queue.Count()
    return #queue
end

-- Returns whether the queue is actively processing operations.
-- @return (boolean) True if the queue is running and not paused.
function MR.Queue.IsRunning()
    return queueRunning and not isPaused
end
