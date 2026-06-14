module TileType
  PATH  = :path
  WALL  = :wall
  START = :start
  GOAL  = :goal
end

module DrawMode
  DRAW_WALL = :draw_wall
  ERASE     = :erase_wall
  SET_START = :set_start
  SET_END   = :set_end
end

class Tile
  attr_accessor :col, :row, :tile_type

  def initialize(col, row, tile_type = TileType::PATH)
    @col       = col
    @row       = row
    @tile_type = tile_type
  end
end

# grid creation

def create_grid(rows, cols, tile_size)
  grid = []
  rows.times do |row|
    grid[row] = []
    cols.times do |col|
      grid[row][col] = Tile.new(col, row)
    end
  end
  grid
end

# tile creation

def set_tile(grid, col, row, tile_type)
  return unless valid_position?(grid, col, row)
  grid[row][col].tile_type = tile_type
end

def wall_at?(grid, col, row)
  return true unless valid_position?(grid, col, row)
  grid[row][col].tile_type == TileType::WALL
end

def valid_position?(grid, col, row)
  row >= 0 && row < grid.length &&
  col >= 0 && col < grid[0].length
end

def tile_at_pixel(grid, px, py, tile_size, offset_x = 0, offset_y = 0)
  col = ((px - offset_x) / tile_size).to_i
  row = ((py - offset_y) / tile_size).to_i
  return nil unless valid_position?(grid, col, row)
  grid[row][col]
end

def clear_grid(grid)
  grid.each { |row| row.each { |tile| tile.tile_type = TileType::PATH } }
end

def find_start(grid)
  grid.each { |row| row.each { |tile| return tile if tile.tile_type == TileType::START } }
  nil
end

def find_goal(grid)
  grid.each { |row| row.each { |tile| return tile if tile.tile_type == TileType::GOAL } }
  nil
end

# bfs distance map

def precompute_distances(grid, goal_col, goal_row)
  distances = {}
  queue     = [[goal_col, goal_row, 0]]

  until queue.empty?
    col, row, dist = queue.shift
    next if distances[[col, row]]
    next unless valid_position?(grid, col, row)
    next if grid[row][col].tile_type == TileType::WALL

    distances[[col, row]] = dist

    [[0, -1], [0, 1], [-1, 0], [1, 0]].each do |dc, dr|
      nc = col + dc
      nr = row + dr
      queue << [nc, nr, dist + 1] unless distances[[nc, nr]]
    end
  end

  distances
end

# save/load

def save_maze(grid, filename = "maze.txt")
  File.open(filename, 'w') do |f|
    f.puts "#{grid.length},#{grid[0].length}"
    grid.each do |row|
      f.puts row.map { |t|
        case t.tile_type
        when TileType::WALL  then 'W'
        when TileType::START then 'S'
        when TileType::GOAL  then 'G'
        else '.'
        end
      }.join
    end
  end
end

def load_maze(grid, filename = "maze.txt")
  return false unless File.exist?(filename)

  lines      = File.readlines(filename).map(&:chomp)
  rows, cols = lines[0].split(',').map(&:to_i)
  return false unless rows == grid.length && cols == grid[0].length

  lines[1..].each_with_index do |line, row|
    line.chars.each_with_index do |char, col|
      type = case char
             when 'W' then TileType::WALL
             when 'S' then TileType::START
             when 'G' then TileType::GOAL
             else TileType::PATH
             end
      set_tile(grid, col, row, type)
    end
  end

  true
end