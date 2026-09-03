{
  config,
  lib,
  pkgs,
  ...
}: let
  palette = import ../../lib/palette.nix;
in {
  # btop configuration managed manually to allow custom theme
  xdg.configFile."btop/btop.conf".text = ''
    color_theme = "rose-pine-dawn"
    theme_background = True
    vim_keys = True
    rounded_corners = True
    graph_symbol = "braille"
    shown_boxes = "cpu mem net proc"
    update_ms = 2000
    proc_sorting = "cpu lazy"
    proc_tree = False
    proc_colors = True
    proc_gradient = True
    proc_per_core = False
    proc_mem_bytes = True
    cpu_graph_upper = "total"
    cpu_graph_lower = "total"
    cpu_invert_lower = True
    cpu_single_graph = False
    cpu_bottom = False
    show_cpu_freq = True
    show_cpu_temp = True
    check_temp = True
    thermal_zone = 0
    show_coretemp = True
    cpu_core_map = ""
    show_uptime = True
    show_watts = True
    mem_graphs = True
    mem_below_net = False
    show_swap = True
    swap_disk = True
    show_disks = True
    only_physical = True
    use_fstab = True
    zfs_arc_cached = True
    disk_free_priv = False
    show_io_stat = True
    io_mode = False
    io_graph_combined = False
    io_graph_speeds = ""
    net_download = 100
    net_upload = 100
    net_auto = True
    net_sync = True
    net_iface = ""
    show_battery = True
    show_battery_watts = True
    log_level = "warning"
  '';

  # Rose Pine Dawn theme for btop
  xdg.configFile."btop/themes/rose-pine-dawn.theme".text = ''
    # Rose Pine Dawn theme for btop
    # Main background, empty for terminal default
    theme[main_bg]="${palette.background}"

    # Main text color
    theme[main_fg]="${palette.text}"

    # Title color for boxes
    theme[title]="${palette.text}"

    # Highlight color for selected items
    theme[hi_fg]="${palette.love}"

    # Background color of selected item in processes box
    theme[selected_bg]="${palette.overlay}"

    # Foreground color of selected item in processes box
    theme[selected_fg]="${palette.text}"

    # Color of inactive/disabled text
    theme[inactive_fg]="${palette.mutedText}"

    # Misc colors for processes box including mini graphs
    theme[proc_misc]="${palette.foam}"

    # Cpu box outline color
    theme[cpu_box]="${palette.foam}"

    # Memory/disks box outline color
    theme[mem_box]="${palette.iris}"

    # Net up/down box outline color
    theme[net_box]="${palette.pine}"

    # Processes box outline color
    theme[proc_box]="${palette.rose}"

    # Box divider line and small boxes line color
    theme[div_line]="${palette.highlightMed}"

    # Temperature graph colors
    theme[temp_start]="${palette.pine}"
    theme[temp_mid]="${palette.gold}"
    theme[temp_end]="${palette.love}"

    # CPU graph colors
    theme[cpu_start]="${palette.pine}"
    theme[cpu_mid]="${palette.foam}"
    theme[cpu_end]="${palette.love}"

    # Mem/Disk free meter
    theme[free_start]="${palette.pine}"
    theme[free_mid]="${palette.foam}"
    theme[free_end]="${palette.iris}"

    # Mem/Disk cached meter
    theme[cached_start]="${palette.pine}"
    theme[cached_mid]="${palette.foam}"
    theme[cached_end]="${palette.iris}"

    # Mem/Disk available meter
    theme[available_start]="${palette.pine}"
    theme[available_mid]="${palette.foam}"
    theme[available_end]="${palette.iris}"

    # Mem/Disk used meter
    theme[used_start]="${palette.pine}"
    theme[used_mid]="${palette.foam}"
    theme[used_end]="${palette.love}"

    # Download graph colors
    theme[download_start]="${palette.pine}"
    theme[download_mid]="${palette.foam}"
    theme[download_end]="${palette.iris}"

    # Upload graph colors
    theme[upload_start]="${palette.pine}"
    theme[upload_mid]="${palette.foam}"
    theme[upload_end]="${palette.iris}"

    # Process box color gradient for threads, mem and cpu usage
    theme[process_start]="${palette.pine}"
    theme[process_mid]="${palette.foam}"
    theme[process_end]="${palette.love}"
  '';
}
