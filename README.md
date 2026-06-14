# GA_maze_pathfinder
A visual genetic algorithm simulation built in Ruby with Gosu. Watch a population of dots evolve over generations to find the optimal path through a user-drawn maze.

# How it works
Dots start at a user-defined point with randomised movement instructions (DNA). Each generation, dots follow their DNA through the maze. Dots that get closer to the goal score higher fitness. The best performers reproduce — passing their genes to the next generation through crossover and mutation. Over hundreds of generations, the population converges on an efficient path.
The mutation rate is dynamic — it decays logarithmically as generations progress, with position-biased gene protection that shields early converged steps from randomisation. This addresses the exploration-exploitation tradeoff inherent in canonical genetic algorithms.

# Features
Draw your own maze on a customisable grid canvas
Set start and goal tiles
Real-time visualisation — dots colour-coded by fitness (red → yellow → green)
Best path traced across generations
Live fitness graph showing convergence over time
Dynamic vs fixed mutation rate toggle — for experimental comparison
Step-through mode for frame-by-frame inspection
Maze save and load
CSV export of generation data for research analysis

