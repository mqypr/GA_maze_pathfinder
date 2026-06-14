def area_clicked(mx, my, x, y, w, h)
  mx >= x && mx < x + w && my >= y && my < y + h
end

def handle_mouse_down(mx, my, draw_mode, grid, tile_size, offset_x, offset_y, edit_mode)
  return unless edit_mode
  tile = tile_at_pixel(grid, mx, my, tile_size, offset_x, offset_y)
  return if tile.nil?

  case draw_mode
  when DrawMode::DRAW_WALL
    unless [TileType::START, TileType::GOAL].include?(tile.tile_type)
      tile.tile_type = TileType::WALL
    end
  when DrawMode::ERASE
    tile.tile_type = TileType::PATH
  end
end