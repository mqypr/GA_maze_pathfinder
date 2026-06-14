require 'gosu'
require_relative 'simulator'
require_relative 'grid'
require_relative 'render'
require_relative 'input'

WINDOW_W    = 1000
WINDOW_H    = 750
PANEL_W     = 220
TOOLBAR_H   = 44
CONTROLS_H  = 52
GRID_AREA_X = 0
GRID_AREA_Y = TOOLBAR_H
GRID_AREA_W = WINDOW_W - PANEL_W
GRID_AREA_H = WINDOW_H - TOOLBAR_H - CONTROLS_H
PANEL_X     = WINDOW_W - PANEL_W

DEFAULT_ROWS     = 20
DEFAULT_COLS     = 20
DEFAULT_POP      = 100
DEFAULT_GEN_LIM  = 200
DEFAULT_MUT      = 0.05
DEFAULT_STAG_LIM = 30

class Window < Gosu::Window
  def initialize
    super(WINDOW_W, WINDOW_H)
    self.caption = "Reach — Genetic Algorithm Maze Pathfinder"

    @font_sm  = Gosu::Font.new(13)
    @font_med = Gosu::Font.new(15)
    @font_lg  = Gosu::Font.new(20)

    @rows      = DEFAULT_ROWS
    @cols      = DEFAULT_COLS
    @tile_size = calc_tile_size
    @grid      = create_grid(@rows, @cols, @tile_size)

    @population       = nil
    @history          = []
    @distance_map     = {}
    @sim_state        = SimState::CONFIGURING
    @generation       = 0
    @mutation_rate    = DEFAULT_MUT
    @base_mut_rate    = DEFAULT_MUT
    @prev_avg_fitness = 0.0
    @best_path        = []
    @snapshot_avg     = nil
    @snapshot_best    = nil

    @goal_col  = nil
    @goal_row  = nil
    @start_col = nil
    @start_row = nil

    @pop_size    = DEFAULT_POP
    @gen_limit   = DEFAULT_GEN_LIM
    @stag_limit  = DEFAULT_STAG_LIM
    @gene_length = 0
    @panel_config_y_gene = nil
    @mut_mode    = MutMode::ADAPTIVE

    @draw_mode  = DrawMode::DRAW_WALL
    @edit_mode  = true
    @mouse_held = false
    @speed      = 1

    @ui_message      = nil
    @ui_message_type = :info

    @panel_config_y_pop  = nil
    @panel_config_y_gen  = nil
    @panel_config_y_mut  = nil
    @panel_config_y_stag = nil
    @panel_config_y_rows = nil
    @panel_config_y_cols = nil
    @panel_mut_mode_y    = nil
  end

  def update
    if @mouse_held && @edit_mode &&
       @sim_state != SimState::RUNNING && in_grid_canvas?(mouse_x, mouse_y)
      handle_mouse_down(
        mouse_x, mouse_y, @draw_mode, @grid,
        @tile_size, grid_offset_x, grid_offset_y, @edit_mode
      )
    end

    return unless @sim_state == SimState::RUNNING
    return if @goal_col.nil?

    @speed.times do
      break unless @sim_state == SimState::RUNNING

      if generation_complete?(@population)
        end_generation
      else
        update_dots(@population, @grid, @goal_col, @goal_row)
      end
    end
  end

  def step_once
    return unless @sim_state == SimState::PAUSED
    return if @population.nil? || @goal_col.nil?
    if generation_complete?(@population)
      end_generation
      @sim_state = SimState::PAUSED unless @sim_state == SimState::FINISHED
    else
      update_dots(@population, @grid, @goal_col, @goal_row)
    end
  end

  def draw
    Gosu.draw_rect(0, 0, WINDOW_W, WINDOW_H, C_BG, 0)
    draw_grid(@grid, @tile_size, grid_offset_x, grid_offset_y)
    draw_best_path(@best_path, @tile_size, grid_offset_x, grid_offset_y)
    draw_dots(@population, @tile_size, grid_offset_x, grid_offset_y)
    draw_toolbar
    draw_controls
    draw_panel(build_stats, self, @font_sm, @font_lg, PANEL_X, PANEL_W, WINDOW_H)
  end

  def button_down(id)
    case id
    when Gosu::MS_LEFT
      @mouse_held = true

      if mouse_y < TOOLBAR_H
        handle_toolbar_click(mouse_x, mouse_y)

      elsif mouse_y >= WINDOW_H - CONTROLS_H
        handle_controls_click(mouse_x, mouse_y)

      elsif mouse_x >= PANEL_X
        handle_panel_click(mouse_x, mouse_y)

      elsif in_grid_canvas?(mouse_x, mouse_y) && @edit_mode &&
            @sim_state != SimState::RUNNING
        tile = tile_at_pixel(@grid, mouse_x, mouse_y,
                             @tile_size, grid_offset_x, grid_offset_y)
        if tile
          case @draw_mode
          when DrawMode::SET_START
            @grid.each { |r| r.each { |t| t.tile_type = TileType::PATH if t.tile_type == TileType::START } }
            tile.tile_type = TileType::START
            @draw_mode = DrawMode::DRAW_WALL
          when DrawMode::SET_END
            @grid.each { |r| r.each { |t| t.tile_type = TileType::PATH if t.tile_type == TileType::GOAL } }
            tile.tile_type = TileType::GOAL
            @draw_mode = DrawMode::DRAW_WALL
          end
        end
      end

    when Gosu::MS_RIGHT
      if @edit_mode && @sim_state != SimState::RUNNING && in_grid_canvas?(mouse_x, mouse_y)
        tile = tile_at_pixel(@grid, mouse_x, mouse_y,
                             @tile_size, grid_offset_x, grid_offset_y)
        tile.tile_type = TileType::PATH if tile
      end

    when Gosu::KB_SPACE
      toggle_sim

    when Gosu::KB_R
      reset_sim if stopped?

    when Gosu::KB_C
      if @edit_mode && stopped?
        clear_grid(@grid)
        reset_cached_positions
        set_message("Grid cleared", :info)
      end

    when Gosu::KB_S
      save_maze(@grid)
      set_message("Saved to maze.txt", :info)
      puts "Saved to maze.txt"

    when Gosu::KB_L
      if stopped?
        if load_maze(@grid)
          @edit_mode = true
          reset_cached_positions
          set_message("Loaded maze.txt", :info)
          puts "Loaded maze.txt"
        else
          set_message("Load failed — check maze.txt", :error)
        end
      end

    when Gosu::KB_TAB
      step_once

    when Gosu::KB_RIGHT
      step_once

    when Gosu::KB_1 then adj_config(:pop_size,  -10)    if stopped?
    when Gosu::KB_2 then adj_config(:pop_size,  +10)    if stopped?
    when Gosu::KB_3 then adj_config(:gen_limit, -10)    if stopped?
    when Gosu::KB_4 then adj_config(:gen_limit, +10)    if stopped?
    when Gosu::KB_5 then adj_config(:mut,       -0.005) if stopped?
    when Gosu::KB_6 then adj_config(:mut,       +0.005) if stopped?
    when Gosu::KB_7 then adj_config(:stag,      -5)     if stopped?
    when Gosu::KB_8 then adj_config(:stag,      +5)     if stopped?
    when Gosu::KB_9 then toggle_mut_mode                if stopped?
    end
  end

  def button_up(id)
    @mouse_held = false if id == Gosu::MS_LEFT
  end

  private

  def stopped?
    @sim_state != SimState::RUNNING
  end

  def calc_tile_size
    [GRID_AREA_W / @cols, GRID_AREA_H / @rows].min
  end

  def grid_offset_x
    GRID_AREA_X + (GRID_AREA_W - @tile_size * @cols) / 2
  end

  def grid_offset_y
    GRID_AREA_Y + (GRID_AREA_H - @tile_size * @rows) / 2
  end

  def in_grid_canvas?(mx, my)
    mx >= grid_offset_x && mx < grid_offset_x + @tile_size * @cols &&
    my >= grid_offset_y && my < grid_offset_y + @tile_size * @rows
  end

  def set_message(text, type = :info)
    @ui_message      = text
    @ui_message_type = type
  end

  def reset_cached_positions
    @goal_col     = nil
    @goal_row     = nil
    @start_col    = nil
    @start_row    = nil
    @distance_map = {}
    @best_path    = []
  end

  def rebuild_grid
    @tile_size = calc_tile_size
    @grid      = create_grid(@rows, @cols, @tile_size)
    reset_cached_positions
    reset_sim
    @edit_mode  = true
    @ui_message = nil
    @gene_length = 0
  end

  def adj_config(key, delta)
    case key
    when :pop_size  then @pop_size      = (@pop_size      + delta).clamp(10, 500)
    when :gen_limit then @gen_limit     = (@gen_limit     + delta).clamp(10, 1000)
    when :mut       then @base_mut_rate = (@base_mut_rate + delta).clamp(0.001, 0.5).round(3)
    when :stag      then @stag_limit    = (@stag_limit    + delta).clamp(5, 200)
    when :rows      then @rows = (@rows + delta.to_i).clamp(5, 40); rebuild_grid
    when :cols      then @cols = (@cols + delta.to_i).clamp(5, 40); rebuild_grid
    when :gene_len
      auto = calc_gene_length(@rows, @cols)
      current = @gene_length > 0 ? @gene_length : auto
      @gene_length = (current + delta).clamp(MIN_GENE_LENGTH, MAX_GENE_LENGTH)
    end
  end

  def toggle_mut_mode
    @mut_mode = (@mut_mode == MutMode::ADAPTIVE) ? MutMode::FIXED : MutMode::ADAPTIVE
    set_message("Mutation: #{@mut_mode.to_s.upcase}", :info)
  end

  def build_stats
    if @population
      best     = @snapshot_best || @population.max_by { |d| d.fitness }
      avg      = @snapshot_avg  || @population.sum { |d| d.fitness } / @population.length.to_f
      alive    = @population.count { |d| d.alive }
      reached  = @population.count { |d| d.reached_goal }
      gene_len = @population.first.dna.length
    else
      best = nil; avg = 0.0; alive = 0; reached = 0
      gene_len = @gene_length > 0 ? @gene_length : calc_gene_length(@rows, @cols)
    end

    {
      generation:    @generation,
      population:    @population ? @population.length : 0,
      gene_length:   gene_len,
      mutation_rate: @mutation_rate,
      avg_fitness:   avg,
      best_fitness:  best ? best.fitness : 0.0,
      alive:         alive,
      reached_goal:  reached,
      pop_size:      @pop_size,
      gen_limit:     @gen_limit,
      base_mut:      @base_mut_rate,
      stag_limit:    @stag_limit,
      mut_mode:      @mut_mode,
      sim_state:     @sim_state,
      edit_mode:     @edit_mode,
      rows:          @rows,
      cols:          @cols,
      history:       @history,
      ui_message:    @ui_message,
      ui_msg_type:   @ui_message_type,
      gene_length_override: @gene_length
    }
  end

  # ── Simulation control ───────────────────────────────────────────

  def start_sim
    unless @start_col && @goal_col
      set_message("Place start and goal, then Confirm", :warn)
      return
    end
    if @distance_map.empty?
      set_message("Click Confirm before starting", :warn)
      return
    end

    gene_len = @gene_length > 0 ? @gene_length : calc_gene_length(@rows, @cols)
    @population       = create_population(@pop_size, gene_len)
    reset_population(@population, @start_col, @start_row)
    @history          = []
    @generation       = 0
    @mutation_rate    = @base_mut_rate
    @prev_avg_fitness = 0.0
    @best_path        = []
    @snapshot_avg     = nil
    @snapshot_best    = nil
    @sim_state        = SimState::RUNNING
    @ui_message       = nil

    puts "Started — #{@pop_size} dots, #{gene_len} genes, mut_mode=#{@mut_mode}"
  end

  def toggle_sim
    case @sim_state
    when SimState::RUNNING               then @sim_state = SimState::PAUSED
    when SimState::PAUSED                then @sim_state = SimState::RUNNING
    when SimState::CONFIGURING,
         SimState::FINISHED              then start_sim
    end
  end

  def finish_sim
    return unless @sim_state == SimState::RUNNING || @sim_state == SimState::PAUSED
    return if @population.nil?
    # Evaluate the current generation before closing out
    evaluate_population(@population, @distance_map)
    log_generation(@population, @generation, @mutation_rate, @history)
    @sim_state = SimState::FINISHED
    set_message("Manually finished at gen #{@generation}", :info)
    puts "Manually finished at generation #{@generation}"
    print_results(@history)
    export_history(@history, "results_#{@mut_mode}_gen#{@generation}.csv")
  end

  def reset_sim
    @population    = nil
    @history       = []
    @generation    = 0
    @mutation_rate = @base_mut_rate
    @best_path     = []
    @snapshot_avg  = nil
    @snapshot_best = nil
    @sim_state     = SimState::CONFIGURING
  end

  def confirm_maze
    start_tile = find_start(@grid)
    goal_tile  = find_goal(@grid)
    unless start_tile
      set_message("No start tile placed", :error)
      return
    end
    unless goal_tile
      set_message("No goal tile placed", :error)
      return
    end

    @start_col    = start_tile.col
    @start_row    = start_tile.row
    @goal_col     = goal_tile.col
    @goal_row     = goal_tile.row
    @distance_map = precompute_distances(@grid, @goal_col, @goal_row)

    if @distance_map.length < 2
      set_message("Goal is unreachable from start", :error)
      @goal_col = nil; @goal_row = nil
      @distance_map = {}
      return
    end

    @edit_mode = false
    set_message("#{@distance_map.length} tiles reachable — ready", :info)
    puts "Confirmed — #{@distance_map.length} reachable tiles"
  end

  def begin_edit
    return if @sim_state == SimState::RUNNING
    @edit_mode  = true
    @ui_message = nil
    reset_cached_positions
    reset_sim
  end

  def end_generation
    evaluate_population(@population, @distance_map)

    best = @population.max_by { |d| d.fitness }
    if @best_path.empty? || best.fitness > (@history.last&.best_fitness || 0.0)
      @best_path = best.path.dup
    end

    avg = @population.sum { |d| d.fitness } / @population.length.to_f
    log_generation(@population, @generation, @mutation_rate, @history)
    debug_generation(@population, @generation, @mutation_rate, @history)

    @sim_state = check_stopping_conditions(
      @generation, @gen_limit, @history, @stag_limit
    )

    if @sim_state == SimState::FINISHED
      reason = @generation >= @gen_limit ? "gen limit" : "stagnated"
      set_message("Done — #{reason} at gen #{@generation}", :info)
      puts "Finished after #{@generation} generations (#{reason})"
      print_results(@history)
      export_history(@history, "results_#{@mut_mode}_gen#{@generation}.csv")
      return
    end

    @mutation_rate    = update_mutation_rate(
      @base_mut_rate, avg, @prev_avg_fitness, @generation + 1, @mut_mode
    )
    @prev_avg_fitness = avg
    @snapshot_avg     = avg
    @snapshot_best    = best

    @population = next_generation(@population, @generation, @mutation_rate)
    reset_population(@population, @start_col, @start_row)
    @generation += 1
  end

  # ── Toolbar ──────────────────────────────────────────────────────

  def draw_toolbar
    Gosu.draw_rect(0, 0, WINDOW_W - PANEL_W, TOOLBAR_H, C_PANEL_BG, ZOrder::UI)

    if @edit_mode
      # Edit tools only visible while editing
      [
        { mode: DrawMode::DRAW_WALL, label: "Wall",  x: 10  },
        { mode: DrawMode::ERASE,     label: "Erase", x: 88  },
        { mode: DrawMode::SET_START, label: "Start", x: 166 },
        { mode: DrawMode::SET_END,   label: "End",   x: 244 },
      ].each do |t|
        draw_button(t[:x], 7, 70, 30, t[:label], @draw_mode == t[:mode], @font_sm)
      end

      draw_button(330, 7, 95, 30, "Confirm", false, @font_sm, C_BTN_CONFIRM)
      # Clear is red — destructive, only available in edit mode
      draw_button(434, 7, 70, 30, "Clear",   false, @font_sm, C_BTN_DANGER)
    else
      draw_button(10, 7, 70, 30, "Edit", false, @font_sm, C_BTN)
      @font_sm.draw_text(
        "SPC=run  TAB=step  R=reset  S/L=save/load",
        92, 15, ZOrder::UI + 1, 1, 1, C_TEXT_DIM
      )
    end
  end

  def handle_toolbar_click(mx, my)
    return unless my < TOOLBAR_H

    if @edit_mode
      if    area_clicked(mx, my, 10,  7, 70, 30) then @draw_mode = DrawMode::DRAW_WALL
      elsif area_clicked(mx, my, 88,  7, 70, 30) then @draw_mode = DrawMode::ERASE
      elsif area_clicked(mx, my, 166, 7, 70, 30) then @draw_mode = DrawMode::SET_START
      elsif area_clicked(mx, my, 244, 7, 70, 30) then @draw_mode = DrawMode::SET_END
      elsif area_clicked(mx, my, 330, 7, 95, 30) then confirm_maze
      elsif area_clicked(mx, my, 434, 7, 70, 30) && stopped?
        clear_grid(@grid)
        reset_cached_positions
        set_message("Grid cleared", :info)
      end
    else
      begin_edit if area_clicked(mx, my, 10, 7, 70, 30)
    end
  end

  # control bar

  def draw_controls
    cy = WINDOW_H - CONTROLS_H
    Gosu.draw_rect(0, cy, WINDOW_W - PANEL_W, CONTROLS_H, C_PANEL_BG, ZOrder::UI)
    by = cy + 10

    # Context button — Start / Pause / Resume / Edit
    label, color = case @sim_state
                   when SimState::RUNNING  then ["Pause",  C_BTN_DANGER]
                   when SimState::PAUSED   then ["Resume", C_BTN_CONFIRM]
                   when SimState::FINISHED then ["Edit",   C_BTN]
                   else                        ["Start",  C_BTN_CONFIRM]
                   end
    draw_button(10,  by, 80, 32, label,   false, @font_sm, color)
    draw_button(100, by, 80, 32, "Reset", false, @font_sm)

    # Step
    step_color = @sim_state == SimState::PAUSED ? C_BTN : Gosu::Color.new(255, 35, 35, 42)
    step_text  = @sim_state == SimState::PAUSED ? C_TEXT : C_TEXT_DIM
    draw_button(190, by, 80, 32, "Step", false, @font_sm, step_color)

    # Finish
    can_finish = @sim_state == SimState::RUNNING || @sim_state == SimState::PAUSED
    fin_color  = can_finish ? C_BTN_WARN : Gosu::Color.new(255, 35, 35, 42)
    draw_button(280, by, 80, 32, "Finish", false, @font_sm, fin_color)

    @font_sm.draw_text("Speed:", 375, by + 10, ZOrder::UI + 1, 1, 1, C_TEXT_DIM)
    draw_button(420, by, 26, 32, "-", false, @font_sm)
    @font_sm.draw_text(@speed.to_s, 452, by + 10, ZOrder::UI + 1, 1, 1, C_TEXT)
    draw_button(468, by, 26, 32, "+", false, @font_sm)

    if @sim_state == SimState::PAUSED
      @font_sm.draw_text("TAB/→ = step", 504, by + 10, ZOrder::UI + 1, 1, 1, C_TEXT_DIM)
    end
  end

  def handle_controls_click(mx, my)
    cy = WINDOW_H - CONTROLS_H
    return unless my >= cy
    by = cy + 10

    if area_clicked(mx, my, 10, by, 80, 32)
      @sim_state == SimState::FINISHED ? begin_edit : toggle_sim

    elsif area_clicked(mx, my, 100, by, 80, 32)
      reset_sim if stopped?

    elsif area_clicked(mx, my, 190, by, 80, 32)
      step_once 

    elsif area_clicked(mx, my, 280, by, 80, 32)
      finish_sim

    elsif area_clicked(mx, my, 420, by, 26, 32)
      @speed = [@speed - 1, 1].max

    elsif area_clicked(mx, my, 468, by, 26, 32)
      @speed = [@speed + 1, 30].min
    end
  end

  # panel click

  def handle_panel_click(mx, my)
    return unless stopped?

    bw       = 20
    bh       = 16
    bx_minus = PANEL_X + 154
    bx_plus  = PANEL_X + 178

    [
      { key: :pop_size,  delta: 10,    y: @panel_config_y_pop  },
      { key: :gen_limit, delta: 10,    y: @panel_config_y_gen  },
      { key: :mut,       delta: 0.005, y: @panel_config_y_mut  },
      { key: :stag,      delta: 5,     y: @panel_config_y_stag },
      { key: :rows,      delta: 1,     y: @panel_config_y_rows },
      { key: :cols,      delta: 1,     y: @panel_config_y_cols },
      { key: :gene_len, delta: 10, y: @panel_config_y_gene },
    ].each do |cfg|
      next unless cfg[:y]
      if area_clicked(mx, my, bx_minus, cfg[:y], bw, bh)
        adj_config(cfg[:key], -cfg[:delta])
      elsif area_clicked(mx, my, bx_plus, cfg[:y], bw, bh)
        adj_config(cfg[:key], +cfg[:delta])
      end
    end

    if @panel_mut_mode_y && area_clicked(mx, my, PANEL_X + 14, @panel_mut_mode_y, PANEL_W - 28, 18)
      toggle_mut_mode
    end
  end
end 

Window.new.show
