#!/bin/bash

# Paths
input_folder="/Users/Lou/Desktop/FFmpeg"
output_folder="${input_folder}/overviews"
google_sheet_url="[FILE_URL]/pub?gid=0&single=true&output=csv"
csv_file="${output_folder}/data.csv"
mkdir -p "$output_folder"

# Configurable Settings
font_file="${input_folder}/Roboto.ttf"  # Path to the font file
frames_per_row=4                        # Number of frames per row in the final montage
output_width=900                        # Assumed output width for positioning
output_height=1700                      # Assumed output height for positioning
summary_metrics_y_offset_start=1000     # Initial y-offset for summary metrics
font_summary_size=60                    # Font size for summary metrics
summary_font_color="white"              # Font color for text
timestamp_font_size=80                  # Font size for timestamp text
timestamp_font_color="white"            # Font color for timestamp
position_timestamp_x="0.75"             # Timestamp horizontal position as a percentage of width
position_timestamp_y="0.1"              # Timestamp vertical position as a percentage of height
play_metric_font_size=120               # Font size for play metrics
play_metric_font_color="orange"         # Font color for play metrics
background_color="black@0.7"            # Background box color and transparency for all metrics and text
display_play_curve="Y"                  # Display play curve graph (Y/N)
position_playcurve_x=50                 # X position of play curve on first frame
position_playcurve_y=800                # Y position of play curve on first frame
create_gif="Y"                          # Set to "Y" to create a GIF, "N" to skip GIF creation


# Check if the CSV file exists locally; if not, download it from the Google Sheets URL
if [[ ! -f "$csv_file" ]]; then
    echo "Local CSV file not found. Downloading from Google Sheets..."
    curl -o "$csv_file" "$google_sheet_url"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download CSV from Google Sheets."
        exit 1
    fi
else
    echo "Using local CSV file at $csv_file"
fi

# Function to create play curve graph using gnuplot
generate_play_curve_graph() {
    local graph_output="${output_folder}/play_curve_graph.png"
    local plot_data="${output_folder}/play_curve_data.txt"
    
    # Prepare data file for gnuplot
    > "$plot_data"
    for i in "${!valid_intervals[@]}"; do
        echo "${valid_intervals[$i]} ${play_metric_values[$i]}" >> "$plot_data"
    done
    
    # Generate graph with gnuplot, including shaded benchmark areas
    gnuplot <<EOF
        set terminal png size 800,600
        set output "$graph_output"
        set title "Play Curve"
        set xlabel "Seconds"
        set ylabel "Play Metric (%)"
        
        # Define shaded areas with color overlays
        set object 1 rectangle from 2,0 to 4,20 fc rgb "red" fillstyle solid 0.3 noborder       # Red for 0-20%
        set object 2 rectangle from 2,20 to 4,40 fc rgb "yellow" fillstyle solid 0.3 noborder   # Yellow for 20-40%
        set object 3 rectangle from 2,40 to 4,100 fc rgb "green" fillstyle solid 0.3 noborder   # Green for 40% and above

        # Plot the play curve line
        plot "$plot_data" using 1:2 with lines title 'Play Curve' lw 4 linecolor "black"
EOF
    echo "$graph_output"
}


# Read CSV and extract metrics for summary and play curve
tail -n +2 "$csv_file" | while IFS=, read -r campaign_name ad_set_name ad_name cost avg_watch_time ctr conversion_rate \
    play_curve_0 play_curve_1 play_curve_2 play_curve_3 play_curve_4 play_curve_5 play_curve_6 play_curve_7 \
    play_curve_8 play_curve_9 play_curve_10 play_curve_11 play_curve_12 play_curve_13 play_curve_14 \
    play_curve_15_20 play_curve_20_25 play_curve_25_30 play_curve_30_40 play_curve_40_50 play_curve_50_60 play_curve_60_more; do

    video_file="${input_folder}/${ad_name}.mp4"
    if [ ! -f "$video_file" ]; then
        echo "Video file $video_file not found, skipping."
        continue
    fi

    # Generate intervals and valid play metrics
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file" | awk '{print int($1)}')
    intervals=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 20 25 30 40 50 60)
    valid_intervals=()
    play_curve_values=("$play_curve_0" "$play_curve_1" "$play_curve_2" "$play_curve_3" "$play_curve_4" \
                       "$play_curve_5" "$play_curve_6" "$play_curve_7" "$play_curve_8" "$play_curve_9" \
                       "$play_curve_10" "$play_curve_11" "$play_curve_12" "$play_curve_13" "$play_curve_14" \
                       "$play_curve_15_20" "$play_curve_20_25" "$play_curve_25_30" "$play_curve_30_40" \
                       "$play_curve_40_50" "$play_curve_50_60" "$play_curve_60_more")

    play_metric_values=()
    for i in "${!intervals[@]}"; do
        t=${intervals[$i]}
        if (( t <= duration )); then
            valid_intervals+=("$t")
            play_metric_values+=("${play_curve_values[$i]}")
        fi
    done

    # Generate the play curve graph for the summary image
    summary_image="${output_folder}/${ad_name}_summary.jpg"
    if [[ "$display_play_curve" == "Y" ]]; then
        play_curve_image=$(generate_play_curve_graph)
        
        # Create the summary image with play curve and metrics
        ffmpeg -i "$video_file" -i "$play_curve_image" -filter_complex \
            "[0][1]overlay=${position_playcurve_x}:${position_playcurve_y}, \
             drawtext=text='Avg Watch Time\: ${avg_watch_time}':x=10:y=(h-$summary_metrics_y_offset_start):fontsize=$font_summary_size:fontcolor=$summary_font_color:box=1:boxcolor=$background_color:fontfile=$font_file, \
             drawtext=text='CTR\: ${ctr}':x=10:y=(h-$summary_metrics_y_offset_start-100):fontsize=$font_summary_size:fontcolor=$summary_font_color:box=1:boxcolor=$background_color:fontfile=$font_file, \
             drawtext=text='Conversion Rate\: ${conversion_rate}':x=10:y=(h-$summary_metrics_y_offset_start-200):fontsize=$font_summary_size:fontcolor=$summary_font_color:box=1:boxcolor=$background_color:fontfile=$font_file" \
            -update 1 -frames:v 1 "$summary_image"
    else
        # Create the summary image without play curve
        ffmpeg -i "$video_file" -update 1 -frames:v 1 \
            -vf "drawtext=text='Avg Watch Time\: ${avg_watch_time}':x=10:y=(h-$summary_metrics_y_offset_start):fontsize=$font_summary_size:fontcolor=$summary_font_color:box=1:boxcolor=$background_color:fontfile=$font_file, \
                 drawtext=text='CTR\: ${ctr}':x=10:y=(h-$summary_metrics_y_offset_start-100):fontsize=$font_summary_size:fontcolor=$summary_font_color:box=1:boxcolor=$background_color:fontfile=$font_file, \
                 drawtext=text='Conversion Rate\: ${conversion_rate}':x=10:y=(h-$summary_metrics_y_offset_start-200):fontsize=$font_summary_size:fontcolor=$summary_font_color:box=1:boxcolor=$background_color:fontfile=$font_file" \
            "$summary_image"
    fi

    # Now create frames with timestamps and play metrics
    frame_images=()
    for i in "${!valid_intervals[@]}"; do
        t=${valid_intervals[$i]}
        play_metric=${play_metric_values[$i]}
        [ -z "$play_metric" ] && play_metric="N/A"

        frame_image="${output_folder}/${ad_name}_frame_${t}.jpg"
        frame_images+=("$frame_image")

        x_position=$(echo "$t / $duration * $output_width" | bc -l)
        y_position=$(echo "(1 - $play_metric / 100) * $output_height" | bc -l)
        min_y_position=$(echo "$output_height * 0.2" | bc -l)
        [ $(echo "$y_position > $output_height - $min_y_position" | bc -l) -eq 1 ] && y_position=$(echo "$output_height - $min_y_position" | bc -l)

        timestamp_x=$(echo "$output_width * $position_timestamp_x" | bc)
        timestamp_y=$(echo "$output_height * $position_timestamp_y" | bc)

        ffmpeg -ss "$t" -i "$video_file" -vframes 1 -q:v 2 -update 1 \
            -vf "drawtext=text='${t}s':x=$timestamp_x:y=$timestamp_y:fontsize=$timestamp_font_size:fontcolor=$timestamp_font_color:box=1:boxcolor=$background_color:fontfile=$font_file, \
                 drawtext=text='${play_metric}':x=$x_position:y=$y_position:fontsize=$play_metric_font_size:fontcolor=$play_metric_font_color:box=1:boxcolor=$background_color:fontfile=$font_file" \
            "$frame_image"
    done

    # Generate a timestamp for the output filename
    timestamp=$(date +"%Y%m%d_%H%M%S")

    # Create the final overview image with the specified number of frames per row
    montage -geometry +2+2 -tile "${frames_per_row}x" "${summary_image}" "${frame_images[@]}" "${output_folder}/${ad_name}_overview_${timestamp}.jpg"

    ## Conditionally create a GIF based on the `create_gif` setting
    if [[ "$create_gif" == "Y" ]]; then
    echo "Creating GIF with timestamp: $timestamp"
    ffmpeg -i "${output_folder}/${ad_name}_frame_%d.jpg" -vf "scale=320:-1,setpts=PTS*12" \
    "${output_folder}/${ad_name}_animated_${timestamp}.gif"
    else
    echo "GIF creation is disabled. Skipping GIF generation."
    fi

    # Clean up individual frames and play curve files
    rm "${frame_images[@]}"
    rm "$summary_image"
    rm "${output_folder}/play_curve_graph.png" "${output_folder}/play_curve_data.txt"
done
