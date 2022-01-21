using FFMPEG
using ProgressMeter
#using DaggerGPU
#using Distributed
#using JuliaConVideoManager

# Hello world with FFMPEG 
#FFMPEG.exe("-version")
#postervideos = pkgdir(JuliaConVideoManager, "src/postervideos")
postervideos = "/home/miguelraz/JuliaConVideoManager/src/postervideos"
outdir = "/home/jpsamaroo/processed"
mkpath(outdir)

# Let's try to run the bare bash script with no GPUs
files = readdir(postervideos) 
intro = files[files .== "intro.mp4"] |> only
# Ugly to have such stateful transformations but meh
files = filter(x -> !startswith("intro", x), files)
@show files[1]
@show intro

#FFMPEG.exe("ffmpeg -i $postervideos/$intro -filter_complex \"[0:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:-1:-1,setsar=1,fps=30,format=yuv420p\" -map \"[v]\" -map \"[a]\" -c:v libx264 -c:a aac -movflags +faststart $outdir/intro_final.mp4")

function recipe(target, intro, cpus, gpu)
    gpu_selector = gpu === nothing ? "" : " -gpu $gpu"
    String.(split("""-y -i $postervideos/intro.mp4 -i $postervideos/$target -threads $cpus -filter_complex [0:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:-1:-1,setsar=1,fps=30,format=yuv420p[v0];[1:v]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:-1:-1,setsar=1,fps=30,format=yuv420p[v1];[v0][0:a][v1][1:a]concat=n=2:v=1:a=1[v][a] -map [v] -map [a]$gpu_selector -c:v h264_nvenc -c:a aac -movflags +faststart $outdir/$target""", ' '))
end

progress = Progress(length(files), 1)

bottleneck = get(ENV, "BOTTLENECK", "cpu")
if bottleneck == "cpu"
# CPU is bottleneck
@sync for (cpu, f_batch) in enumerate(Iterators.partition(files, Sys.CPU_THREADS))
    @async for file in f_batch
        # Use the select CPU, and any GPU
        redirect_stderr(devnull) do
            FFMPEG.exe(recipe(file, intro, cpu, nothing)...)
        end
        next!(progress)
    end
end

else

# GPU is bottleneck
#using CUDA
GPUS = 3
@sync for (gpu, f_batch) in enumerate(Iterators.partition(files, GPUS))
    @async for file in f_batch
        # Use the selected GPU, and an equivalent amount of CPU threads
        redirect_stderr(devnull) do
            FFMPEG.exe(recipe(file, intro, div(Sys.CPU_THREADS, GPUS), gpu-1)...)
        end
        next!(progress)
    end
end
end
