import Dates
import Libdl
import Random

function unzip_whl(whl_path::String, output_dir::String)
    @info "Extracting $(whl_path) to $(output_dir)..."
    run(`unzip -q $(whl_path) -d $(output_dir)`)
    @info "Extraction complete."
end

function find_libpath(dir::String, libname::String, prefixes::Vector{String})
    for prefix in prefixes
        test_path = joinpath(dir, prefix, libname)
        if isfile(test_path)
            return test_path
        end
    end
    return ""
end

function download_whl(
    package_name::String,
    temp_download_dir::String;
    version::Union{String,Nothing}=nothing,
)
    @info "Downloading $(package_name) wheel to $(temp_download_dir)..."
    try
        pip_cmd = "pip"
        cmd = `$pip_cmd download $package_name$(isnothing(version) ? "" : "==$version") --dest $temp_download_dir --no-deps`
        run(cmd)
        @info "Download complete for $(package_name)."

    catch e
        @error "Error downloading package $(package_name): $e"
        rethrow(e)
    end

    wheel_files = filter(f -> endswith(f, ".whl"), readdir(temp_download_dir))

    if isempty(wheel_files)
        @error "No wheel file found for $(package_name) in $(temp_download_dir)"
        error("No wheel file found.")
    end

    if length(wheel_files) > 1
        @warn "Multiple wheel files found. This implies '--no-deps' might not have been fully effective or other files were present. Using the first one: $(wheel_files[1])"
    end

    return joinpath(temp_download_dir, wheel_files[1])
end

function try_wheel_installation(; version::String="15.0.0")
    @info "Attempting wheel installation..."

    knitro_package_name = "knitro"

    temp_download_base = joinpath(tempdir(), "knitro_temp")
    temp_download_id = string(Dates.now(), "_", Random.randstring(8))
    download_dir_path = joinpath(temp_download_base, temp_download_id)
    mkpath(download_dir_path)

    exctract_dir = joinpath(@__DIR__, "knitro")

    try
        # Step 1: Download the Knitro wheel using pip
        knitro_wheel_path =
            download_whl(knitro_package_name, download_dir_path; version=version)

        # Step 2: Prepare the extraction directory
        @info "Preparing extraction directory: $(exctract_dir)"
        if ispath(exctract_dir)
            @info "Existing extraction directory '$(exctract_dir)' found. Deleting contents."
            rm(exctract_dir, recursive=true, force=true)
        end
        mkpath(exctract_dir)

        # Step 3: Unzip the wheel file
        unzip_whl(knitro_wheel_path, exctract_dir)

        # Step 4: Locate the library within the extracted structure
        libname = string(Sys.iswindows() ? "" : "lib", "knitro", ".", Libdl.dlext)

        # Step 5: Locate the library within the extracted structure
        libprefixes = ["", "lib", "knitro/lib"]
        libpath = find_libpath(exctract_dir, libname, libprefixes)

        if isempty(libpath)
            @error "Could not find Knitro library ($(libname)) within the extracted wheel content at $(exctract_dir)."
            error("Knitro library not found.")
        end
        @info "Found Knitro library at: $(libpath)"

        deps_path = dirname(dirname(libpath))

        write_depsfile(deps_path, libpath)
        @info "Knitro wheel installation complete and deps.jl updated."
    catch e
        @error "Knitro wheel installation failed: $e"
        write_depsfile("", "")
    finally
        if ispath(download_dir_path)
            @info "Cleaning up temporary download directory: $(download_dir_path)"
            rm(download_dir_path, recursive=true, force=true)
            if isempty(readdir(temp_download_base))
                rm(temp_download_base)
            end
        end
    end
    return
end
