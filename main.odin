package main

import json "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"

SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 480

GAME_WIDTH :: 320
GAME_HEIGHT :: 240

TILE_SIZE :: 16

PLAYER_MOVE_SPEED :: 50
PLAYER_HEALTH :: 5

MainState :: enum {
	PAUSED,
	MAINMENU,
	GAMEOVER,
	LEVEL0,
	LEVEL1,
	LEVEL2,
	LEVEL3,
	LEVEL4,
}

PlayerAnimationState :: enum {
	IDLE,
	RUNNING_W,
	RUNNING_S,
	RUNNING_A,
	RUNNING_D,
	DEACTIVE,
	ACTIVE,
}

TileType :: enum {
	WALL,
	GROUND,
	SURGROUND,
	PROPS,
}

EntityType :: enum {
	PLAYER,
	MONSTER,
	ROPE,
	FIREPIT,
}

AnimationPlayer :: struct {
	state:          PlayerAnimationState,
	frame:          int,
	timer:          f32,
	frame_count:    int,
	frame_duration: f32,
}

Entity :: struct {
	position:             rl.Vector2,
	animationPlayer:      ^AnimationPlayer,
	texture_id:           rl.Texture2D,
	type:                 EntityType,

	//players
	movedir:              rl.Vector2,
	health:               int,

	//rope
	pickable:             bool,
	already_picked:       bool,

	//fire
	fire_active:          bool,
	show_interact_prompt: bool,
}

TileSet :: struct {
	first_gid: int,
	texture:   rl.Texture2D,
	tileType:  TileType,
}

LevelData :: struct {
	level_id:                  int,
	player_start_position:     rl.Vector2,
	lift_trigger_pos:          rl.Vector2,
	lift_trigger_dimentions:   rl.Vector2,
	//pickable ropes	
	rope_count_exists:         int,
	current_picked_rope_count: int,
	//
	locked:                    bool,
	won:                       bool,
}

State :: struct {
	current_state:            MainState,
	player:                   Entity,
	map_json:                 TiledMap,
	tilesets:                 []TileSet,
	map_width:                int,
	map_height:               int,
	tile_width:               int,
	tile_height:              int,
	tile_data:                []int,
	prop_data:                []int,
	camera:                   rl.Camera2D,
	render_texture:           rl.RenderTexture2D,
	fullscreen:               bool,
	levels:                   [5]LevelData,
	last_level:               int,
	//FONT
	main_font:                rl.Font,
	//SOUND
	sounds:                   map[string]rl.Sound,
	music:                    map[string]rl.Music,
	master_volume:            f32,
	is_muted:                 bool,
	audio_device_initialized: bool,
	//enemies+firepit+rope
	texture_efr:              rl.Texture2D,
	enemies:                  [dynamic]Entity,
	ropes:                    [dynamic]Entity,
	firepits:                 [dynamic]Entity,
	show_firepit_prompt:      bool,
	nearest_firepit_index:    int,
	//light shader
	light_shader:             rl.Shader,
	light_pos_loc:            i32,
	light_radius_loc:         i32,
	screen_size_loc:          i32,
	light_radius:             f32,
	max_light_radius:         f32,
	light_timer:              f32,
	light_duration:           f32,
	camera_pos_loc:           i32,
	player_pos_loc:           i32,
	render_size_loc:          i32,
}

TiledLayerObjectProperties :: struct {
	name:  string,
	type:  string,
	value: int,
}

TiledLayerObjects :: struct {
	id:         int,
	height:     f32,
	width:      f32,
	name:       string,
	properties: []TiledLayerObjectProperties,
	rotation:   int,
	x:          f32,
	y:          f32,
}

TiledLayerTile :: struct {
	id:      int,
	name:    string,
	type:    string, // should be "tilelayer"
	data:    []int,
	width:   int,
	height:  int,
	x:       int,
	y:       int,
	opacity: f32,
	visible: bool,
	objects: []TiledLayerObjects,
}

TiledMap :: struct {
	compressionlevel: int,
	height:           int,
	width:            int,
	tilewidth:        int,
	tileheight:       int,
	infinite:         bool,
	nextlayerid:      int,
	nextobjectid:     int,
	orientation:      string,
	renderorder:      string,
	tiledversion:     string,
	type:             string,
	version:          string,
	layers:           []TiledLayerTile, // you can also use []TiledLayer* if manually decoded
}

state: State

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "ld57")
	defer rl.CloseWindow()

	state.render_texture = rl.LoadRenderTexture(GAME_WIDTH, GAME_HEIGHT)
	defer rl.UnloadRenderTexture(state.render_texture)
	// Set window state
	state.fullscreen = false
	rl.SetWindowState({.WINDOW_RESIZABLE})

	init_game()
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		handle_input()
		update_game()
		draw_game()
	}
}


handle_input :: proc() {
	dt := rl.GetFrameTime()

	// Toggle fullscreen with F11 (available in all states)
	if rl.IsKeyPressed(.F11) {
		state.fullscreen = !state.fullscreen
		if state.fullscreen {
			monitor := rl.GetCurrentMonitor()
			rl.SetWindowSize(rl.GetMonitorWidth(monitor), rl.GetMonitorHeight(monitor))
			rl.ToggleFullscreen()
		} else {
			rl.ToggleFullscreen()
			rl.SetWindowSize(SCREEN_WIDTH, SCREEN_HEIGHT)
		}
	}

	switch state.current_state {
	case .MAINMENU:
		if rl.IsKeyPressed(.SPACE) {
			change_level(1) // Start from level 0
		}

	case .LEVEL0, .LEVEL1, .LEVEL2, .LEVEL3, .LEVEL4:
		// Player movement controls
		new_pos := state.player.position

		if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {
			new_pos.y -= PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_W
		} else if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) {
			new_pos.y += PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_S
		} else if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
			new_pos.x += PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_D
		} else if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
			new_pos.x -= PLAYER_MOVE_SPEED * dt
			state.player.animationPlayer.state = .RUNNING_A
		} else {
			state.player.animationPlayer.state = .IDLE
		}

		// Only update position if new position is not blocked
		if !is_tile_blocking(new_pos) {
			state.player.position = new_pos
			// Update movedir only if movement was successful
			state.player.movedir = {
				new_pos.x - state.player.position.x,
				new_pos.y - state.player.position.y,
			}
		}

		// Pause game
		if rl.IsKeyPressed(.P) {
			state.current_state = .PAUSED
		}

		check_firepit_interaction()

	case .PAUSED:
		if rl.IsKeyPressed(.P) || rl.IsKeyPressed(.SPACE) {
			if state.last_level >= 0 && state.last_level < 5 {
				state.current_state = MainState(int(MainState.LEVEL0) + state.last_level)

			}
		}
		if rl.IsKeyPressed(.M) {
			state.current_state = .MAINMENU
		}

	case .GAMEOVER:
		if rl.IsKeyPressed(.SPACE) {
			// Restart game
			change_level(0)
		}
		if rl.IsKeyPressed(.M) {
			state.current_state = .MAINMENU
		}
	}
}

update_game :: proc() {
	if state.current_state == .PAUSED ||
	   state.current_state == .MAINMENU ||
	   state.current_state == .GAMEOVER {
		return // Don't update game logic in these states
	}

	// Update camera to follow player
	state.camera.target = state.player.position
	state.camera.offset = {GAME_WIDTH / 2, GAME_HEIGHT / 2}

	// Keep camera within map bounds
	max_x := f32(state.map_width * state.tile_width) - GAME_WIDTH / 2
	max_y := f32(state.map_height * state.tile_height) - GAME_HEIGHT / 2

	state.camera.target.x = math.clamp(state.camera.target.x, GAME_WIDTH / 2, max_x)
	state.camera.target.y = math.clamp(state.camera.target.y, GAME_HEIGHT / 2, max_y)
	update_firepits()
}

init_game :: proc() {
	state.current_state = .MAINMENU

	state.camera = rl.Camera2D {
		zoom     = 1.0,
		rotation = 0.0,
		offset   = {GAME_WIDTH / 2, GAME_HEIGHT / 2},
		target   = {0, 0},
	}

	// Initialize player position
	state.player.type = .PLAYER
	state.player.position = {100, 100}
	state.player.texture_id = rl.LoadTexture("assets/elf.png")
	state.player.animationPlayer = new(AnimationPlayer)
	state.player.animationPlayer.frame = 0
	state.player.animationPlayer.timer = 0
	state.player.animationPlayer.frame_count = 3
	state.player.animationPlayer.frame_duration = 0.1
	state.player.animationPlayer.state = .IDLE
	state.player.health = PLAYER_HEALTH

	state.texture_efr = rl.LoadTexture("assets/fire-enemy-rope.png")


	if parsed_json, ok := os.read_entire_file("assets/map.json", context.temp_allocator); ok {
		// if err := json.unmarshal(parsed_json, &state.map_json); err != nil {
		// 	fmt.eprintln("Failed to unmarshal JSON:", err)
		// 	os.exit(1) // Exit with error code
		// }

		if json.unmarshal(parsed_json, &state.map_json) == nil {

			state.tile_width = state.map_json.tilewidth
			state.tile_height = state.map_json.tileheight
			state.map_width = state.map_json.width
			state.map_height = state.map_json.height

			for layer in state.map_json.layers {
				if layer.id == 1 {
					state.tile_data = layer.data
				} else if layer.id == 5 {
					state.prop_data = layer.data
				}
			}

			walls_texture := rl.LoadTexture("assets/walls.png")
			grounds_texture := rl.LoadTexture("assets/grounds.png")
			surgrounds_texture := rl.LoadTexture("assets/surground.png")
			props_texture := rl.LoadTexture("assets/props.png")
			state.tilesets = make([]TileSet, 4, context.allocator)
			state.tilesets[0] = TileSet {
				first_gid = 1,
				texture   = walls_texture,
				tileType  = .WALL,
			}
			state.tilesets[1] = TileSet {
				first_gid = 225,
				texture   = grounds_texture,
				tileType  = .GROUND,
			}
			state.tilesets[2] = TileSet {
				first_gid = 433,
				texture   = surgrounds_texture,
				tileType  = .SURGROUND,
			}
			state.tilesets[3] = TileSet {
				first_gid = 615,
				texture   = props_texture,
				tileType  = .PROPS,
			}
		} else {
			fmt.println("Failed to unmarshal JSON")
		}

	} else {
		fmt.println("Failed to read my_struct_file")
	}
	//map user position for different levels
	for layer in state.map_json.layers {
		switch layer.name {
		case "playerstart":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						state.levels[level_id].player_start_position = {obj.x, obj.y}
						state.levels[level_id].level_id = level_id
					}
				}
			}

		case "lift":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						state.levels[level_id].lift_trigger_pos = {obj.x, obj.y}
						state.levels[level_id].lift_trigger_dimentions = {
							f32(obj.width),
							f32(obj.height),
						}
					}
				}
			}
		case "rope":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						state.levels[level_id].rope_count_exists += 1
						rope := Entity {
							position       = {obj.x, obj.y},
							type           = .ROPE,
							pickable       = true,
							already_picked = false,
							texture_id     = state.texture_efr, // Your rope texture
						}
						append(&state.ropes, rope)
					}
				}
			}
		case "enemy":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						enemy_animation_player := new(AnimationPlayer)
						enemy_animation_player.state = .IDLE
						enemy_animation_player.frame = 3
						enemy_animation_player.timer = 0
						enemy_animation_player.frame_count = 3
						enemy_animation_player.frame_duration = 0.5
						enemy := Entity {
							position        = {obj.x, obj.y},
							type            = .MONSTER,
							texture_id      = state.texture_efr, // Your rope texture
							movedir         = {1, 0},
							animationPlayer = enemy_animation_player,
						}
						append(&state.enemies, enemy)
					}
				}
			}
		case "firepit":
			for obj in layer.objects {
				if obj.properties != nil && len(obj.properties) > 0 {
					level_id := obj.properties[0].value
					if level_id >= 0 && level_id < len(state.levels) {
						firepit_animation_player := new(AnimationPlayer)
						firepit_animation_player.state = .DEACTIVE
						firepit_animation_player.frame = 0
						firepit_animation_player.timer = 0
						firepit_animation_player.frame_count = 1
						firepit_animation_player.frame_duration = 0.5
						firepit := Entity {
							position        = {obj.x, obj.y},
							type            = .FIREPIT,
							texture_id      = state.texture_efr,
							fire_active     = false,
							animationPlayer = firepit_animation_player,
						}
						append(&state.firepits, firepit)
					}
				}
			}
		}
	}

	//light shader
	state.light_shader = rl.LoadShader("", "lighting.fs")


	state.player_pos_loc = rl.GetShaderLocation(state.light_shader, "playerPos")
	state.light_radius_loc = rl.GetShaderLocation(state.light_shader, "lightRadius")
	state.render_size_loc = rl.GetShaderLocation(state.light_shader, "renderSize")
	// Set screen size once
	screen_size := [2]f32{f32(GAME_WIDTH), f32(GAME_HEIGHT)}
	rl.SetShaderValue(state.light_shader, state.screen_size_loc, &screen_size, .VEC2)
	state.max_light_radius = 10.0
	state.light_radius = state.max_light_radius
	state.light_duration = 10.0 // Seconds until light fades
	state.light_timer = state.light_duration

	//sounds

	//enemies

}

draw_game :: proc() {
	// Draw to our render texture (game resolution)
	rl.BeginTextureMode(state.render_texture)
	{
		rl.ClearBackground(rl.BLACK)
		if state.current_state >= .LEVEL0 && state.current_state <= .LEVEL4 {
			rl.BeginMode2D(state.camera)
			{
				// Draw map tiles
				for y in 0 ..< state.map_height {
					for x in 0 ..< state.map_width {
						idx := y * state.map_width + x
						gid := state.tile_data[idx]
						if gid == 0 {
							continue
						}

						// Find the appropriate tileset
						tileset: ^TileSet = nil
						best_gid := -1
						for &ts in state.tilesets {
							if ts.first_gid <= gid && ts.first_gid > best_gid {
								tileset = &ts
								best_gid = ts.first_gid
							}
						}

						if tileset == nil {
							continue
						}

						local_id := gid - tileset.first_gid
						tileset_columns := int(tileset.texture.width) / state.tile_width
						tileset_rows := int(tileset.texture.height) / state.tile_height

						if local_id < 0 || local_id >= tileset_columns * tileset_rows {
							continue
						}

						src := rl.Rectangle {
							f32((local_id % tileset_columns) * state.tile_width),
							f32((local_id / tileset_columns) * state.tile_height),
							f32(state.tile_width),
							f32(state.tile_height),
						}
						dest := rl.Vector2{f32(x * state.tile_width), f32(y * state.tile_height)}

						rl.DrawTextureRec(tileset.texture, src, dest, rl.WHITE)
					}
				}
				//props tile layer
				for y in 0 ..< state.map_height {
					for x in 0 ..< state.map_width {
						idx := y * state.map_width + x
						gid := state.prop_data[idx]
						if gid == 0 {
							continue
						}

						// Find the appropriate tileset
						tileset: ^TileSet = nil
						best_gid := -1
						for &ts in state.tilesets {
							if ts.first_gid <= gid && ts.first_gid > best_gid {
								tileset = &ts
								best_gid = ts.first_gid
							}
						}

						if tileset == nil {
							continue
						}

						local_id := gid - tileset.first_gid
						tileset_columns := int(tileset.texture.width) / state.tile_width
						tileset_rows := int(tileset.texture.height) / state.tile_height

						if local_id < 0 || local_id >= tileset_columns * tileset_rows {
							continue
						}

						src := rl.Rectangle {
							f32((local_id % tileset_columns) * state.tile_width),
							f32((local_id / tileset_columns) * state.tile_height),
							f32(state.tile_width),
							f32(state.tile_height),
						}
						dest := rl.Vector2{f32(x * state.tile_width), f32(y * state.tile_height)}

						rl.DrawTextureRec(tileset.texture, src, dest, rl.WHITE)
					}
				}
				//animation player
				{
					anim := state.player.animationPlayer

					// Update animation timer
					anim.timer += rl.GetFrameTime()
					if anim.timer >= anim.frame_duration {
						anim.timer = 0
						anim.frame = (anim.frame + 1) % anim.frame_count
					}

					// Calculate frame position in sprite sheet
					frame_x := f32(anim.frame * TILE_SIZE)
					frame_y: f32 = 0 // Default row for IDLE

					// Select animation row based on state
					#partial switch anim.state {
					case .RUNNING_W:
						anim.frame_count = 4
						frame_y = f32(2 * TILE_SIZE)
					case .RUNNING_S:
						anim.frame_count = 4
						frame_y = f32(2 * TILE_SIZE)
					case .RUNNING_A:
						anim.frame_count = 4
						frame_y = f32(3 * TILE_SIZE)
					case .RUNNING_D:
						anim.frame_count = 4
						frame_y = f32(2 * TILE_SIZE)
					case .IDLE:
						anim.frame_count = 3
						frame_y = 0
					}

					player_src := rl.Rectangle{frame_x, frame_y, f32(TILE_SIZE), f32(TILE_SIZE)}

					player_pixel_pos := rl.Vector2 {
						state.player.position.x,
						state.player.position.y,
					}

					rl.DrawTextureRec(
						state.player.texture_id,
						player_src,
						player_pixel_pos,
						rl.WHITE,
					)
				}
				//animations enemy
				{
					for enemy in state.enemies {
						anim := enemy.animationPlayer

						// Update animation timer
						anim.timer += rl.GetFrameTime()
						if anim.timer >= anim.frame_duration {
							anim.timer = 0
							anim.frame = (anim.frame + 1) % anim.frame_count
						}

						frames_per_row := state.texture_efr.width / TILE_SIZE
						frame_col := i32(anim.frame) % frames_per_row
						frame_row := 2 // 3rd row (0-indexed)

						frame_x := f32(frame_col * TILE_SIZE)
						frame_y := f32(frame_row * TILE_SIZE)

						e_src := rl.Rectangle{frame_x, frame_y, f32(TILE_SIZE), f32(TILE_SIZE)}

						e_pixel_pos := rl.Vector2{enemy.position.x, enemy.position.y}

						// Optional: Flip texture based on movement direction
						flip := enemy.movedir.x < 0 ? -1.0 : 1.0
						rl.DrawTextureRec(
							state.texture_efr,
							e_src,
							e_pixel_pos,
							rl.ColorAlpha(rl.WHITE, flip < 0 ? 1.0 : 1.0), // Could add flip logic here
						)
					}

				}
				//animations firepit
				{
					for fp in state.firepits {
						anim := fp.animationPlayer
						anim.timer += rl.GetFrameTime()

						frames_per_row := state.texture_efr.width / TILE_SIZE
						frame_col: i32
						frame_row: i32 = 1 // Second row (0-indexed) for firepits
						frame_x: f32
						frame_y: f32

						#partial switch anim.state {
						case .ACTIVE:
							anim.frame_count = 5 // Total frames in row
							// Skip first frame (start at frame 1 instead of 0)
							adjusted_frame := anim.frame + 1
							if adjusted_frame >= anim.frame_count {
								adjusted_frame = 1 // Skip frame 0 when wrapping around
							}
							frame_col = i32(adjusted_frame) % frames_per_row
							frame_y = f32(frame_row * TILE_SIZE)

						case .DEACTIVE:
							anim.frame_count = 1
							frame_col = 0 // First frame
							frame_y = f32(frame_row * TILE_SIZE) // Same row but only first frame
						}

						// Update animation frame
						if anim.timer >= anim.frame_duration {
							anim.timer = 0
							anim.frame = (anim.frame + 1) % anim.frame_count
						}

						frame_x = f32(frame_col * TILE_SIZE)
						f_src := rl.Rectangle{frame_x, frame_y, f32(TILE_SIZE), f32(TILE_SIZE)}
						f_pixel_pos := rl.Vector2{fp.position.x, fp.position.y}

						// Draw base firepit
						rl.DrawTextureRec(state.texture_efr, f_src, f_pixel_pos, rl.WHITE)

						// Add glowing effect for active firepits
						if anim.state == .ACTIVE {
							rl.BeginBlendMode(.ADDITIVE)
							glow_alpha := 0.6 + 0.2 * math.sin(rl.GetTime() * 3) // Pulsing effect
							rl.DrawTextureRec(
								state.texture_efr,
								f_src,
								f_pixel_pos,
								rl.ColorAlpha(rl.ORANGE, f32(glow_alpha)),
							)
							rl.EndBlendMode()
						}
					}
				}
				draw_firepits_tooltip()

				// In draw_game() after BeginMode2D()
				// if ODIN_DEBUG {
				// 	// Draw player collision box
				// 	rl.DrawRectangleLinesEx(
				// 		rl.Rectangle {
				// 			state.player.position.x + 3,
				// 			state.player.position.y + 3,
				// 			f32(state.tile_width - 6),
				// 			f32(state.tile_height - 6),
				// 		},
				// 		1,
				// 		rl.RED,
				// 	)
				//
				// 	// Draw blocking tiles
				// 	for y in 0 ..< state.map_height {
				// 		for x in 0 ..< state.map_width {
				// 			idx := y * state.map_width + x
				// 			gid := state.tile_data[idx]
				// 			gid2 := state.prop_data[idx]
				// 			if gid <= 225 || (gid2 > 615) {
				// 				rl.DrawRectangleLines(
				// 					i32(x * state.tile_width),
				// 					i32(y * state.tile_height),
				// 					i32(state.tile_width),
				// 					i32(state.tile_height),
				// 					rl.ColorAlpha(rl.RED, 0.5),
				// 				)
				// 			}
				// 		}
				// 	}
				// }

			}

			rl.EndMode2D()
		}
		// Draw state-specific overlays
		#partial switch state.current_state {
		case .MAINMENU:
			draw_main_menu()
		case .PAUSED:
			draw_pause_menu()
		case .GAMEOVER:
			draw_game_over()
		}
	}
	rl.EndTextureMode()

	// 3. Now draw your game scene with blending


	// Draw render texture to screen, scaled properly
	rl.BeginDrawing()
	{
		rl.ClearBackground(rl.BLACK)

		// Calculate scaling to maintain aspect ratio
		scale := min(
			f32(rl.GetScreenWidth()) / GAME_WIDTH,
			f32(rl.GetScreenHeight()) / GAME_HEIGHT,
		)

		dest_rect := rl.Rectangle {
			(f32(rl.GetScreenWidth()) - (GAME_WIDTH * scale)) * 0.5,
			(f32(rl.GetScreenHeight()) - (GAME_HEIGHT * scale)) * 0.5,
			GAME_WIDTH * scale,
			GAME_HEIGHT * scale,
		}

		rl.BeginShaderMode(state.light_shader)
		{
			// Set shader uniforms
			//player_pos := [2]f32{state.player.position.x, state.player.position.y}
			render_size := [2]f32{f32(GAME_WIDTH), f32(GAME_HEIGHT)}
			player_world_pos := state.player.position
			// Correct calculation of player position in screen space
			screen_pos := [2]f32 {
				(player_world_pos.x - state.camera.target.x) + (f32(rl.GetScreenWidth()) * 0.5),
				(player_world_pos.y - state.camera.target.y) + (f32(rl.GetScreenHeight()) * 0.5),
			}

			rl.SetShaderValue(
				state.light_shader,
				state.player_pos_loc,
				&state.player.position,
				.VEC2,
			)
			rl.SetShaderValue(
				state.light_shader,
				state.light_radius_loc,
				&state.light_radius,
				.FLOAT,
			)
			rl.SetShaderValue(state.light_shader, state.render_size_loc, &render_size, .VEC2)

			// Draw a full-screen rectangle that will be affected by our shader
			// rl.DrawRectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, rl.WHITE)
			rl.DrawRectangleRec(
				rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
				rl.WHITE,
			)
			//rl.DrawRectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, rl.WHITE)

			//Draw firepit glows (additive blending)
			rl.BeginBlendMode(.ADDITIVE)
			for firepit in state.firepits {
				if firepit.fire_active {
					// Simple glow effect
					glow_pos := rl.Vector2 {
						(firepit.position.x - state.camera.target.x) +
						(f32(rl.GetScreenWidth()) * 0.5),
						(firepit.position.y - state.camera.target.y) +
						(f32(rl.GetScreenHeight()) * 0.5),
					}
					rl.DrawCircleV(glow_pos, 50.0, rl.ColorAlpha(rl.ORANGE, 0.3))
					rl.DrawCircleV(glow_pos, 30.0, rl.ColorAlpha(rl.YELLOW, 0.5))
				}
			}
			rl.EndBlendMode()
			// Simple glow effect
			rl.BeginBlendMode(.ADDITIVE)
			rl.DrawCircleV(
				state.player.position,
				50.0, // Glow radius
				rl.ColorAlpha(rl.ORANGE, 0.3),
			)
			rl.DrawCircleV(screen_pos, 30.0, rl.ColorAlpha(rl.YELLOW, 0.5))
			rl.EndBlendMode()
		}
		rl.EndShaderMode()
		rl.BeginBlendMode(.MULTIPLIED)
		rl.DrawTexturePro(
			state.render_texture.texture,
			rl.Rectangle{0, 0, GAME_WIDTH, -GAME_HEIGHT}, // Flip Y
			dest_rect,
			rl.Vector2{0, 0},
			0,
			rl.WHITE,
		)
		rl.EndBlendMode()
	}
	rl.EndDrawing()
}

change_level :: proc(level: int) {
	if level == 0 {
		state.current_state = .LEVEL0
		state.player.position = state.levels[0].player_start_position
	} else if level == 1 {
		state.current_state = .LEVEL1
		state.player.position = state.levels[1].player_start_position
	} else if level == 2 {
		state.current_state = .LEVEL2
		state.player.position = state.levels[2].player_start_position
	} else if level == 3 {
		state.current_state = .LEVEL3
		state.player.position = state.levels[3].player_start_position
	} else if level == 4 {
		state.current_state = .LEVEL4
		state.player.position = state.levels[4].player_start_position
	}

	// Store last level for pause resume
	state.last_level = level
}
draw_main_menu :: proc() {
	rl.DrawText("MAIN MENU", GAME_WIDTH / 2 - 100, GAME_HEIGHT / 2 - 50, 40, rl.WHITE)
	rl.DrawText("Press SPACE to start", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 20, 20, rl.WHITE)
}

draw_pause_menu :: proc() {
	rl.DrawRectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, {0, 0, 0, 200}) // Semi-transparent overlay
	rl.DrawText("PAUSED", GAME_WIDTH / 2 - 80, GAME_HEIGHT / 2 - 40, 40, rl.WHITE)
	rl.DrawText("Press P to resume", GAME_WIDTH / 2 - 100, GAME_HEIGHT / 2 + 20, 20, rl.WHITE)
	rl.DrawText("Press M for main menu", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 50, 20, rl.WHITE)
}
draw_game_over :: proc() {
	rl.DrawRectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, {0, 0, 0, 200})
	rl.DrawText("GAME OVER", GAME_WIDTH / 2 - 100, GAME_HEIGHT / 2 - 40, 40, rl.RED)
	rl.DrawText("Press SPACE to restart", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 20, 20, rl.WHITE)
	rl.DrawText("Press M for main menu", GAME_WIDTH / 2 - 120, GAME_HEIGHT / 2 + 50, 20, rl.WHITE)
}

is_tile_blocking :: proc(pos: rl.Vector2) -> bool {
	// Check all four corners of the player's hitbox
	points := []rl.Vector2 {
		{pos.x + 3, pos.y + 3}, // top-left
		{(pos.x + 3) + 10, (pos.y + 3)}, // top-right
		{(pos.x + 3), (pos.y + 3) + 10}, // bottom-left
		{(pos.x + 3) + 10, (pos.y + 3) + 10}, // bottom-right
	}


	for point in points {
		tile_x := int(point.x) / state.tile_width
		tile_y := int(point.y) / state.tile_height

		// Check bounds
		if tile_x < 0 || tile_x >= state.map_width || tile_y < 0 || tile_y >= state.map_height {
			return true
		}

		// Get tile data
		idx := tile_y * state.map_width + tile_x
		gid := state.tile_data[idx]
		gid2 := state.prop_data[idx]

		// Check if tile is blocking
		if gid <= 225 || (gid2 > 615) {
			return true
		}
	}
	return false
}
update_firepits :: proc() {
	state.nearest_firepit_index = -1 // Reset each frame
	state.show_firepit_prompt = false

	// Find the nearest interactable firepit
	closest_distance: f32 = max(f32) // Initialize with max possible distance
	for fp, i in state.firepits {
		distance := rl.Vector2Distance(state.player.position, fp.position)
		activation_radius := f32(state.tile_width * 1)

		if distance <= activation_radius && fp.animationPlayer.state == .DEACTIVE {
			if distance < closest_distance {
				closest_distance = distance
				state.nearest_firepit_index = i
			}
		}
	}

	// Show prompt for nearest firepit
	if state.nearest_firepit_index != -1 {
		fp := &state.firepits[state.nearest_firepit_index]
		fp.show_interact_prompt = true
		state.show_firepit_prompt = true

		// Activate specific firepit on E press
		if rl.IsKeyPressed(.E) {
			fp.animationPlayer.state = .ACTIVE
			fp.animationPlayer.frame_count = 5
			fp.animationPlayer.frame = 1 // Skip first frame
			fp.fire_active = true
			//play_sound("fire_ignite")

			// Optional light boost
			//state.light_timer = min(state.light_timer + 20, state.light_duration)
		}
	}

	// Update animations for all active firepits
	for &fp in state.firepits {
		if fp.animationPlayer.state == .ACTIVE {
			fp.animationPlayer.timer += rl.GetFrameTime()
			if fp.animationPlayer.timer >= fp.animationPlayer.frame_duration {
				fp.animationPlayer.timer = 0
				fp.animationPlayer.frame =
					(fp.animationPlayer.frame + 1) % fp.animationPlayer.frame_count

				// Skip frame 0
				if fp.animationPlayer.frame == 0 {
					fp.animationPlayer.frame = 1
				}
			}
		}
	}
}

draw_firepits_tooltip :: proc() {
	for fp in state.firepits {
		// Draw firepit base
		frame_row := 1 // Second row for firepit animations
		frame_col := i32(fp.animationPlayer.frame) % (state.texture_efr.width / TILE_SIZE)
		frame_x := f32(frame_col * TILE_SIZE)
		frame_y := f32(frame_row * TILE_SIZE)

		f_src := rl.Rectangle{frame_x, frame_y, f32(TILE_SIZE), f32(TILE_SIZE)}
		rl.DrawTextureRec(state.texture_efr, f_src, fp.position, rl.WHITE)

		// Draw effects if active
		if fp.fire_active {
			// Glow effect
			rl.BeginBlendMode(.ADDITIVE)
			glow_alpha := 0.5 + 0.2 * math.sin(rl.GetTime() * 3)
			rl.DrawTextureRec(
				state.texture_efr,
				f_src,
				fp.position,
				rl.ColorAlpha(rl.ORANGE, f32(glow_alpha)),
			)
			rl.EndBlendMode()

			// Light effect on environment
			// if rl.CheckCollisionPointCircle(state.player.position, fp.position, 100) {
			// 	state.light_radius = max(state.light_radius, 150) // Extend light radius
			// }
		}

		// Draw interaction prompt
		if fp.show_interact_prompt && !fp.fire_active {
			text_pos := rl.Vector2{fp.position.x - 30, fp.position.y - 25}
			rl.DrawTextEx(state.main_font, "[E] Light", text_pos, 14, 1, rl.WHITE)
		}
	}
}
check_firepit_interaction :: proc() {
	if rl.IsKeyPressed(.R) {
		for &firepit in state.firepits {
			if rl.CheckCollisionCircles(
				state.player.position,
				30.0, // Interaction range
				firepit.position,
				f32(state.tile_width),
			) {
				// Reset light timer
				state.light_timer = state.light_duration
				state.light_radius = state.max_light_radius

				// Visual feedback
				firepit.fire_active = true
				//play_sound("fire_relight")
			}
		}
	}
}
update_light_decay :: proc(dt: f32) {
	// Only decay if not near firepit
	near_firepit := false
	for firepit in state.firepits {
		if firepit.fire_active &&
		   rl.CheckCollisionCircles(
			   state.player.position,
			   state.light_radius,
			   firepit.position,
			   f32(state.tile_width * 2),
		   ) {
			near_firepit = true
			break
		}
	}

	if !near_firepit {
		state.light_timer -= dt
		if state.light_timer < 0 do state.light_timer = 0
		state.light_radius = state.max_light_radius * (state.light_timer / state.light_duration)
	}
}
