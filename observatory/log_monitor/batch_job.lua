local file_reader = require("observatory.log_monitor.file_reader")

local batch_job = {}

function batch_job.start(files)
    return {
        files           = files,
        file_index      = 1,
        lines           = nil,
        line_index      = 1,
        total_files     = #files,
        processed_lines = 0,
    }
end

local function ensure_lines_loaded(job)
    if job.lines then return job.files[job.file_index] end
    local fpath = job.files[job.file_index]
    if not fpath then return nil end
    job.lines = file_reader.read_all_lines(fpath)
    job.line_index = 1
    return fpath
end

local function consume_pending(job, fpath, remaining, process_line)
    local count = #job.lines
    while remaining > 0 and job.line_index <= count do
        process_line(job.lines[job.line_index], fpath)
        job.line_index = job.line_index + 1
        job.processed_lines = job.processed_lines + 1
        remaining = remaining - 1
    end
    return remaining, count
end

local function close_file_if_done(job, fpath, line_count, state)
    if job.line_index <= line_count then return end
    file_reader.mark_consumed(state, fpath)
    job.file_index = job.file_index + 1
    job.lines = nil
end

function batch_job.step(state, job, budget, process_line)
    if not job then return false end
    local remaining = budget
    while remaining > 0 do
        local fpath = ensure_lines_loaded(job)
        if not fpath then return false end
        local count
        remaining, count = consume_pending(job, fpath, remaining, process_line)
        close_file_if_done(job, fpath, count, state)
    end
    return true
end

function batch_job.snapshot(job)
    if not job then return nil end
    return {
        done            = job.file_index - 1,
        total           = job.total_files,
        processed_lines = job.processed_lines,
    }
end

return batch_job
