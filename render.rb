

module ZOrder
  GRID  = 0
  PATHS = 1
  DOTS  = 2
  ELITE = 3
  UI    = 4
end

# Surfaces
C_BG           = Gosu::Color::BLACK
C_TILE_PATH    = Gosu::Color::WHITE
C_TILE_START   = Gosu::Color::BLUE
C_TILE_GOAL    = Gosu::Color::YELLOW
C_GRID_LINE    = Gosu::Color::GRAY
# Text
C_TEXT         = Gosu::Color::WHITE
C_TEXT_DIM     = Gosu::Color::GRAY
# Buttons / separators
C_BTN          = Gosu::Color::GRAY
C_BTN_ACTIVE   = Gosu::Color::BLUE
C_BTN_CONFIRM  = Gosu::Color::GREEN
C_BTN_DANGER   = Gosu::Color::RED
C_BTN_WARN     = Gosu::Color::YELLOW
# Dots / graph
C_DOT_ELITE    = Gosu::Color::WHITE
C_GRAPH_BEST   = Gosu::Color::GREEN
C_GRAPH_AVG    = Gosu::Color::BLUE

# Aliases
C_PANEL_BG  = C_BG
C_TILE_WALL = C_BG
C_SEPARATOR = C_BTN
C_PATH_LINE = C_TILE_GOAL
C_MSG_INFO  = C_BTN_ACTIVE
C_MSG_WARN  = C_BTN_WARN
C_MSG_ERROR = C_BTN_DANGER

# helper

def dot_color(dot)
  return C_DOT_ELITE            if dot.is_elite
  return Gosu::Color::GREEN     if dot.reached_goal
  return Gosu::Color::GRAY      unless dot.alive
  return Gosu::Color::BLUE      if dot.fitness == 0.0
  if dot.fitness > 0.3
    Gosu::Color::YELLOW
  elsif dot.fitness > 0.05
    Gosu::Color::FUCHSIA
  else
    Gosu::Color::RED
  end
end

def draw_button(x, y, w, h, label, active, font, color = nil)
  c  = color || (active ? C_BTN_ACTIVE : C_BTN)
  Gosu.draw_rect(x, y, w, h, c, ZOrder::UI)
  tx = x + (w - font.text_width(label)) / 2
  ty = y + (h - font.height) / 2
  font.draw_text(label, tx, ty, ZOrder::UI + 1, 1, 1, C_TEXT)
end

# grid

def draw_grid(grid, tile_size, offset_x, offset_y)
  rows = grid.length
  cols = grid[0].length

  grid.each do |row|
    row.each do |tile|
      color = case tile.tile_type
              when TileType::WALL  then C_TILE_WALL
              when TileType::START then C_TILE_START
              when TileType::GOAL  then C_TILE_GOAL
              else C_TILE_PATH
              end
      px = offset_x + tile.col * tile_size
      py = offset_y + tile.row * tile_size
      Gosu.draw_rect(px + 1, py + 1, tile_size - 1, tile_size - 1, color, ZOrder::GRID)
    end
  end

  (cols + 1).times do |c|
    Gosu.draw_rect(offset_x + c * tile_size, offset_y, 1, rows * tile_size, C_GRID_LINE, ZOrder::GRID)
  end
  (rows + 1).times do |r|
    Gosu.draw_rect(offset_x, offset_y + r * tile_size, cols * tile_size, 1, C_GRID_LINE, ZOrder::GRID)
  end
end

# dots

def draw_dots(population, tile_size, offset_x, offset_y)
  return if population.nil?
  r = [tile_size / 4, 3].max

  population.each do |dot|
    next if !dot.alive && !dot.reached_goal
    px    = offset_x + dot.x * tile_size + tile_size / 2
    py    = offset_y + dot.y * tile_size + tile_size / 2
    color = dot_color(dot)
    z     = dot.is_elite ? ZOrder::ELITE : ZOrder::DOTS
    Gosu.draw_rect(px - r, py - r, r * 2, r * 2, color, z)
  end
end

# best path

def draw_best_path(best_path, tile_size, offset_x, offset_y)
  return if best_path.nil? || best_path.length < 2
  best_path.each_cons(2) do |a, b|
    ax = offset_x + a[0] * tile_size + tile_size / 2
    ay = offset_y + a[1] * tile_size + tile_size / 2
    bx = offset_x + b[0] * tile_size + tile_size / 2
    by = offset_y + b[1] * tile_size + tile_size / 2
    Gosu.draw_line(ax, ay, C_PATH_LINE, bx, by, C_PATH_LINE, ZOrder::PATHS)
  end
end

# right panel

def draw_panel(stats, win, font_sm, font_lg, panel_x, panel_w, window_h)
  Gosu.draw_rect(panel_x, 0, panel_w, window_h, C_PANEL_BG, ZOrder::UI)

  x   = panel_x + 14
  y   = 16
  bw  = 20
  bh  = 16
  bx  = panel_x + 154
  bx2 = panel_x + 178

  font_lg.draw_text("REACH", x, y, ZOrder::UI + 1, 1, 1, C_BTN_ACTIVE)
  y += 26
  font_sm.draw_text("GA Maze Pathfinder", x, y, ZOrder::UI + 1, 1, 1, C_TEXT_DIM)
  y += 22

  Gosu.draw_rect(x, y, panel_w - 28, 1, C_SEPARATOR, ZOrder::UI + 1)
  y += 10

  # Single status line
  state_color = case stats[:sim_state]
                when SimState::RUNNING  then C_BTN_CONFIRM
                when SimState::FINISHED then C_BTN_WARN
                else C_BTN_ACTIVE
                end
  state_str = stats[:sim_state].to_s.upcase
  state_str += " (editing)" if stats[:edit_mode] && stats[:sim_state] == SimState::CONFIGURING
  font_sm.draw_text(state_str, x, y, ZOrder::UI + 1, 1, 1, state_color)
  y += 18

  # Message area
  if stats[:ui_message]
    msg_color = case stats[:ui_msg_type]
                when :error then C_MSG_ERROR
                when :warn  then C_MSG_WARN
                else C_MSG_INFO
                end
    font_sm.draw_text(stats[:ui_message], x, y, ZOrder::UI + 1, 1, 1, msg_color)
  end
  y += 16

  Gosu.draw_rect(x, y, panel_w - 28, 1, C_SEPARATOR, ZOrder::UI + 1)
  y += 10

  # Runtime stats
  [
    ["Generation",  stats[:generation].to_s],
    ["Population",  stats[:population].to_s],
    ["Gene Length", stats[:gene_length].to_s],
    ["Mut Rate",    stats[:mutation_rate].round(5).to_s],
    ["Avg Fitness", stats[:avg_fitness].round(5).to_s],
    ["Best Fit",    stats[:best_fitness].round(5).to_s],
    ["Alive",       stats[:alive].to_s],
    ["At Goal",     stats[:reached_goal].to_s],
  ].each do |label, value|
    font_sm.draw_text("#{label}:", x, y, ZOrder::UI + 1, 1, 1, C_TEXT_DIM)
    font_sm.draw_text(value, x + 102, y, ZOrder::UI + 1, 1, 1, C_TEXT)
    y += 17
  end

  Gosu.draw_rect(x, y + 4, panel_w - 28, 1, C_SEPARATOR, ZOrder::UI + 1)
  y += 14

  # Config section
  stopped = stats[:sim_state] != SimState::RUNNING
  font_sm.draw_text("CONFIG", x, y, ZOrder::UI + 1, 1, 1, C_TEXT_DIM)
  y += 16

  config_rows = [
    { ivar: :@panel_config_y_pop,  label: "Pop",  value: stats[:pop_size].to_s            },
    { ivar: :@panel_config_y_gen,  label: "Gens", value: stats[:gen_limit].to_s           },
    { ivar: :@panel_config_y_mut,  label: "Mut",  value: stats[:base_mut].round(3).to_s   },
    { ivar: :@panel_config_y_stag, label: "Stag", value: stats[:stag_limit].to_s          },
    { ivar: :@panel_config_y_rows, label: "Rows", value: stats[:rows].to_s                },
    { ivar: :@panel_config_y_cols, label: "Cols", value: stats[:cols].to_s                },
    { ivar: :@panel_config_y_gene, label: "Gene", value: stats[:gene_length_override] > 0 ? stats[:gene_length_override].to_s : "auto" },
  ]

  config_rows.each do |row|
    btn_color  = stopped ? C_BTN : Gosu::Color::BLACK
    text_color = stopped ? C_TEXT : C_TEXT_DIM
    font_sm.draw_text("#{row[:label]}:", x,      y + 2, ZOrder::UI + 1, 1, 1, C_TEXT_DIM)
    font_sm.draw_text(row[:value],       x + 50, y + 2, ZOrder::UI + 1, 1, 1, C_TEXT)
    Gosu.draw_rect(bx,  y, bw, bh, btn_color, ZOrder::UI)
    Gosu.draw_rect(bx2, y, bw, bh, btn_color, ZOrder::UI)
    font_sm.draw_text("-", bx  + 6, y + 1, ZOrder::UI + 1, 1, 1, text_color)
    font_sm.draw_text("+", bx2 + 5, y + 1, ZOrder::UI + 1, 1, 1, text_color)
    win.instance_variable_set(row[:ivar], y)
    y += 20
  end

  # Mutation mode toggle button
  y += 4
  mut_label = "Mut: #{stats[:mut_mode].to_s.upcase}"
  mut_color = stats[:mut_mode] == MutMode::FIXED ? C_BTN_WARN : C_BTN_CONFIRM
  Gosu.draw_rect(x, y, panel_w - 28, 18, stopped ? mut_color : C_BTN, ZOrder::UI)
  font_sm.draw_text(mut_label, x + 4, y + 3, ZOrder::UI + 1, 1, 1, C_TEXT)
  win.instance_variable_set(:@panel_mut_mode_y, y)
  y += 26

end
