{
  config,
  lib,
  pkgs,
  ...
}: {
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
    theme[main_bg]="#faf4ed"

    # Main text color
    theme[main_fg]="#575279"

    # Title color for boxes
    theme[title]="#575279"

    # Highlight color for selected items
    theme[hi_fg]="#b4637a"

    # Background color of selected item in processes box
    theme[selected_bg]="#f2e9e1"

    # Foreground color of selected item in processes box
    theme[selected_fg]="#575279"

    # Color of inactive/disabled text
    theme[inactive_fg]="#9893a5"

    # Misc colors for processes box including mini graphs
    theme[proc_misc]="#56949f"

    # Cpu box outline color
    theme[cpu_box]="#56949f"

    # Memory/disks box outline color
    theme[mem_box]="#907aa9"

    # Net up/down box outline color
    theme[net_box]="#286983"

    # Processes box outline color
    theme[proc_box]="#d7827e"

    # Box divider line and small boxes line color
    theme[div_line]="#dfdad9"

    # Temperature graph colors
    theme[temp_start]="#286983"
    theme[temp_mid]="#ea9d34"
    theme[temp_end]="#b4637a"

    # CPU graph colors
    theme[cpu_start]="#286983"
    theme[cpu_mid]="#56949f"
    theme[cpu_end]="#b4637a"

    # Mem/Disk free meter
    theme[free_start]="#286983"
    theme[free_mid]="#56949f"
    theme[free_end]="#907aa9"

    # Mem/Disk cached meter
    theme[cached_start]="#286983"
    theme[cached_mid]="#56949f"
    theme[cached_end]="#907aa9"

    # Mem/Disk available meter
    theme[available_start]="#286983"
    theme[available_mid]="#56949f"
    theme[available_end]="#907aa9"

    # Mem/Disk used meter
    theme[used_start]="#286983"
    theme[used_mid]="#56949f"
    theme[used_end]="#b4637a"

    # Download graph colors
    theme[download_start]="#286983"
    theme[download_mid]="#56949f"
    theme[download_end]="#907aa9"

    # Upload graph colors
    theme[upload_start]="#286983"
    theme[upload_mid]="#56949f"
    theme[upload_end]="#907aa9"

    # Process box color gradient for threads, mem and cpu usage
    theme[process_start]="#286983"
    theme[process_mid]="#56949f"
    theme[process_end]="#b4637a"
  '';
}
