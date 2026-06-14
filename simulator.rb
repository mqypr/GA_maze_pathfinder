DIRECTIONS = [
  [ 0, -1],  # north
  [ 0,  1],  # south
  [-1,  0],  # west
  [ 1,  0]   # east
]

GENE_LENGTH_FACTOR  = 1.5
MIN_GENE_LENGTH     = 50
MAX_GENE_LENGTH     = 600
WALL_PENALTY        = 0.05   # fitness penalty per wall hit
STAGNATION_EPSILON  = 0.0001 # minimum improvement to count as progress

module SimState
  CONFIGURING = :configuring
  RUNNING     = :running
  PAUSED      = :paused
  FINISHED    = :finished
end

module MutMode
  ADAPTIVE = :adaptive
  FIXED    = :fixed
end

# data structure

class Dot
  attr_accessor :x, :y, :dna, :gene_index, :alive,
                :reached_goal, :fitness, :is_elite, :path,
                :wall_hits

  def initialize(x, y, gene_length, dna = nil)
    @x            = x
    @y            = y
    @dna          = dna || generate_dna(gene_length)
    @gene_index   = 0
    @alive        = true
    @reached_goal = false
    @fitness      = 0.0
    @is_elite     = false
    @path         = [[x, y]]
    @wall_hits    = 0
  end
end

class GenRecord
  attr_accessor :number, :best_fitness, :avg_fitness,
                :mutation_rate, :dots_reached_goal, :best_path

  def initialize(number, best_fitness, avg_fitness, mutation_rate, dots_reached_goal)
    @number            = number
    @best_fitness      = best_fitness
    @avg_fitness       = avg_fitness
    @mutation_rate     = mutation_rate
    @dots_reached_goal = dots_reached_goal
    @best_path         = []
  end
end

# dna

def generate_dna(gene_length)
  Array.new(gene_length) { DIRECTIONS.sample }
end

def calc_gene_length(rows, cols)
  (rows * cols * GENE_LENGTH_FACTOR).to_i.clamp(MIN_GENE_LENGTH, MAX_GENE_LENGTH)
end

# population

def create_population(size, gene_length)
  Array.new(size) { Dot.new(0, 0, gene_length) }
end

def reset_population(population, start_x, start_y)
  population.each do |dot|
    dot.x            = start_x
    dot.y            = start_y
    dot.gene_index   = 0
    dot.alive        = true
    dot.reached_goal = false
    dot.wall_hits    = 0
    dot.path         = [[start_x, start_y]]
  end
end

# dot update

def update_dots(population, grid, goal_col, goal_row)
  population.each do |dot|
    next unless dot.alive && !dot.reached_goal

    if dot.gene_index >= dot.dna.length
      dot.alive = false
      next
    end

    gene  = dot.dna[dot.gene_index]
    new_x = dot.x + gene[0]
    new_y = dot.y + gene[1]

    if !valid_position?(grid, new_x, new_y) || wall_at?(grid, new_x, new_y)
      dot.wall_hits += 1

    elsif new_x == goal_col && new_y == goal_row
      dot.x = new_x
      dot.y = new_y
      dot.reached_goal = true
      dot.path << [new_x, new_y]

    else
      dot.x = new_x
      dot.y = new_y
      dot.path << [new_x, new_y]
    end

    dot.gene_index += 1
  end
end

def generation_complete?(population)
  population.none? { |dot| dot.alive && !dot.reached_goal }
end

# fitness

def calc_fitness(dot, distance_map)
  wall_penalty = [dot.wall_hits * WALL_PENALTY, 0.9].min

  if dot.reached_goal
    # Speed bonus: finishing in fewer steps scores proportionally higher.
    base = 1.0 + (dot.dna.length.to_f / dot.gene_index.to_f)
    base * (1.0 - wall_penalty)
  else
    dist = distance_map[[dot.x, dot.y]]
    return 0.0 if dist.nil?
    return 1.0 * (1.0 - wall_penalty) if dist == 0
    (1.0 / dist.to_f) * (1.0 - wall_penalty)
  end
end

def evaluate_population(population, distance_map)
  population.each { |dot| dot.fitness = calc_fitness(dot, distance_map) }
end

# selection

def select_parent(population)
  total = population.sum { |dot| dot.fitness }
  return population.sample if total <= 0.0

  pick    = rand * total
  running = 0.0
  population.each do |dot|
    running += dot.fitness
    return dot if running >= pick
  end
  population.last
end

# crossover

def crossover(parent_a, parent_b)
  len   = parent_a.dna.length
  point = rand(1...len)
  parent_a.dna[0...point] + parent_b.dna[point..]
end

# mutation

def calc_gene_consensus(top_dots, position)
  genes_at_pos = top_dots.map { |d| d.dna[position] }.compact
  return 1.0 if genes_at_pos.empty?

  avg_dx   = genes_at_pos.sum { |g| g[0] }.to_f / genes_at_pos.length
  avg_dy   = genes_at_pos.sum { |g| g[1] }.to_f / genes_at_pos.length
  variance = genes_at_pos.sum { |g|
    (g[0] - avg_dx)**2 + (g[1] - avg_dy)**2
  }.to_f / genes_at_pos.length

  [variance / 2.0, 1.0].min
end

def mutate(dna, mutation_rate, top_dots)
  consensus_cache = Array.new(dna.length) { |pos| calc_gene_consensus(top_dots, pos) }

  dna.map.with_index do |gene, position|
    position_weight = (position + 1).to_f / dna.length
    consensus       = consensus_cache[position]
    effective_rate  = mutation_rate * position_weight * consensus
    rand < effective_rate ? DIRECTIONS.sample : gene
  end
end

# ADAPTIVE: decays logarithmically, boosts on plateau
# FIXED:    returns base_rate unchanged every generation
def update_mutation_rate(base_rate, avg_fitness, prev_avg_fitness, generation, mode)
  return base_rate if mode == MutMode::FIXED

  decayed     = base_rate / Math.log(generation + 2)
  improvement = avg_fitness - prev_avg_fitness
  improvement < STAGNATION_EPSILON ? [decayed * 2.0, base_rate].min : decayed
end

# reproduction

def next_generation(population, generation, mutation_rate)
  sorted   = population.sort_by { |d| -d.fitness }
  top_dots = sorted.first(20)
  next_gen = []

  2.times do |i|
    elite          = Dot.new(0, 0, 0, sorted[i].dna.dup)
    elite.fitness  = sorted[i].fitness
    elite.is_elite = true
    next_gen << elite
  end

  while next_gen.length < population.length
    parent_a  = select_parent(population)
    parent_b  = select_parent(population)
    child_dna = crossover(parent_a, parent_b)
    child_dna = mutate(child_dna, mutation_rate, top_dots)
    next_gen  << Dot.new(0, 0, 0, child_dna)
  end

  next_gen
end

# loggin

def log_generation(population, generation, mutation_rate, history)
  best         = population.max_by { |d| d.fitness }
  avg_fitness  = population.sum { |d| d.fitness } / population.length.to_f
  dots_reached = population.count { |d| d.reached_goal }

  record           = GenRecord.new(generation, best.fitness.round(6),
                                   avg_fitness.round(6), mutation_rate.round(6), dots_reached)
  record.best_path = best.path.dup
  history << record
  record
end

# stopping conditions

def check_stopping_conditions(generation, generation_limit, history, stagnation_limit)
  return SimState::FINISHED if generation >= generation_limit

  if history.length >= stagnation_limit
    recent = history.last(stagnation_limit).map(&:best_fitness)
    return SimState::FINISHED if (recent.max - recent.min) < STAGNATION_EPSILON
  end

  SimState::RUNNING
end

# terminal output

def debug_generation(population, generation, mutation_rate, history)
  best         = population.max_by { |d| d.fitness }
  avg_fitness  = population.sum { |d| d.fitness } / population.length.to_f
  dots_reached = population.count { |d| d.reached_goal }
  dots_alive   = population.count { |d| d.alive }
  avg_walls    = population.sum { |d| d.wall_hits }.to_f / population.length

  puts "=" * 50
  puts "  GENERATION #{generation}"
  puts "=" * 50
  puts "  Population:        #{population.length}"
  puts "  Gene length:       #{population.first.dna.length}"
  puts "  Mutation rate:     #{mutation_rate.round(6)}"
  puts "  Dots alive:        #{dots_alive}"
  puts "  Dots reached goal: #{dots_reached}"
  puts "  Best fitness:      #{best.fitness.round(6)}"
  puts "  Avg fitness:       #{avg_fitness.round(6)}"
  puts "  Avg wall hits:     #{avg_walls.round(1)}"
  puts "  Best wall hits:    #{best.wall_hits}"
  puts "  Best position:     (#{best.x}, #{best.y})"

  if history.length >= 2
    delta     = history[-1].avg_fitness - history[-2].avg_fitness
    threshold = [avg_fitness * 0.001, STAGNATION_EPSILON].max
    puts "  Fitness change:    #{delta.round(6)}#{delta.abs < threshold ? '  ⚠ plateau' : ''}"
  end
  puts ""
end

def export_history(history, filename)
  File.open(filename, 'w') do |f|
    f.puts "gen,best_fitness,avg_fitness,mutation_rate,dots_reached,best_path_len"
    history.each do |r|
      f.puts "#{r.number},#{r.best_fitness},#{r.avg_fitness},#{r.mutation_rate},#{r.dots_reached_goal},#{r.best_path.length}"
    end
  end
end

def print_results(history)
  return if history.empty?

  best_overall = history.max_by { |r| r.best_fitness }
  final        = history.last
  cw           = [6, 10, 10, 10, 8, 14]
  divider      = "+" + cw.map { |w| "-" * (w + 2) }.join("+") + "+"
  header       = "| " + ["Gen", "Best Fit", "Avg Fit", "Mut Rate", "Reached", "Best Path Len"]
                   .zip(cw).map { |label, w| label.ljust(w) }.join(" | ") + " |"

  puts ""
  puts "=" * 70
  puts "  RESULTS — #{history.length} generations"
  puts "=" * 70
  puts divider
  puts header
  puts divider

  history.each do |r|
    path_len = r.best_path.length > 0 ? r.best_path.length.to_s : "-"
    star     = r.number == best_overall.number ? "*" : " "
    cols = [
      "#{star}#{r.number}".rjust(cw[0]),
      r.best_fitness.round(6).to_s.ljust(cw[1]),
      r.avg_fitness.round(6).to_s.ljust(cw[2]),
      r.mutation_rate.round(6).to_s.ljust(cw[3]),
      r.dots_reached_goal.to_s.ljust(cw[4]),
      path_len.ljust(cw[5])
    ]
    puts "| " + cols.join(" | ") + " |"
  end

  puts divider
  puts ""
  puts "  * = best generation"
  puts "  Best fitness:    #{best_overall.best_fitness.round(6)} (gen #{best_overall.number})"
  puts "  Final reached:   #{final.dots_reached_goal} dots"
  puts "  Avg fitness end: #{final.avg_fitness.round(6)}"
  puts "=" * 70
  puts ""
end
