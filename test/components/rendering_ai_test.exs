defmodule AshGameServer.Components.RenderingAITest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.Components.Rendering.{Sprite, Animation, Visibility, LOD}
  alias AshGameServer.Components.AI.{AIController, Behavior, Perception}
  
  describe "Sprite component" do
    test "creates sprite from texture" do
      sprite = Sprite.from_texture("player.png", 64, 64)
      
      assert sprite.texture_id == "player.png"
      assert sprite.width == 64
      assert sprite.height == 64
    end
    
    test "creates sprite from sheet region" do
      sprite = Sprite.from_sheet("sprites.png", 0, 32, 16, 16)
      
      assert sprite.source_rect == %{x: 0, y: 32, width: 16, height: 16}
    end
    
    test "validates sprite properties" do
      valid = %Sprite{texture_id: "test.png", width: 32, height: 32}
      assert :ok = Sprite.validate(valid)
      
      invalid = %Sprite{texture_id: "", width: 32, height: 32}
      assert {:error, _} = Sprite.validate(invalid)
    end
    
    test "sets tint and opacity" do
      sprite = Sprite.from_texture("test.png")
      |> Sprite.set_tint(255, 0, 0)
      |> Sprite.set_opacity(0.5)
      
      assert sprite.tint == %{r: 255, g: 0, b: 0, a: 255}
      assert sprite.opacity == 0.5
    end
  end
  
  describe "Animation component" do
    test "creates animation with frames" do
      anim = Animation.new()
      |> Animation.add_animation(:walk, [0, 1, 2, 3], true, 1.0)
      
      assert Map.has_key?(anim.animations, :walk)
    end
    
    test "plays and stops animation" do
      anim = Animation.new()
      |> Animation.add_animation(:idle, [0], true)
      |> Animation.play(:idle)
      
      assert anim.playing
      assert anim.current_animation == :idle
      
      stopped = Animation.stop(anim)
      refute stopped.playing
    end
    
    test "updates animation with delta time" do
      anim = Animation.new()
      |> Animation.add_animation(:test, [
        %{index: 0, duration: 100},
        %{index: 1, duration: 100}
      ], false)
      |> Animation.play(:test)
      
      # Advance time
      updated = Animation.update(anim, 150)
      assert updated.current_frame == 1
      
      # Finish animation
      finished = Animation.update(updated, 150)
      assert finished.finished
    end
    
    test "gets current frame index" do
      anim = Animation.new()
      |> Animation.add_animation(:test, [
        %{index: 5, duration: 100}
      ])
      |> Animation.play(:test)
      
      assert Animation.get_current_frame_index(anim) == 5
    end
  end
  
  describe "Visibility component" do
    test "creates visibility with layer" do
      vis = Visibility.new(:foreground, 10)
      
      assert vis.render_layer == :foreground
      assert vis.render_order == 10
    end
    
    test "shows and hides entity" do
      vis = Visibility.new()
      |> Visibility.hide()
      
      refute vis.visible
      refute Visibility.should_render?(vis)
      
      shown = Visibility.show(vis)
      assert shown.visible
      assert Visibility.should_render?(shown)
    end
    
    test "checks culling distance" do
      vis = %Visibility{cull_distance: 100.0}
      
      refute Visibility.should_cull?(vis, 50.0)
      assert Visibility.should_cull?(vis, 150.0)
      
      # Always render overrides culling
      always = %Visibility{cull_distance: 100.0, always_render: true}
      refute Visibility.should_cull?(always, 150.0)
    end
  end
  
  describe "LOD component" do
    test "creates LOD with custom levels" do
      lod = LOD.new(%{ultra: 25.0})
      
      assert Map.has_key?(lod.levels, :ultra)
      assert lod.levels.ultra == 25.0
    end
    
    test "updates level based on distance" do
      lod = LOD.new()
      
      # Close distance = high detail
      high = LOD.update_level(lod, 30.0)
      assert high.current_level == :high
      
      # Medium distance = medium detail
      medium = LOD.update_level(lod, 75.0)
      assert medium.current_level == :medium
      
      # Far distance = billboard detail
      billboard = LOD.update_level(lod, 300.0)
      assert billboard.current_level == :billboard
    end
    
    test "forces specific LOD level" do
      lod = LOD.new()
      |> LOD.force_level(:billboard)
      
      assert lod.force_level == :billboard
      assert lod.current_level == :billboard
      
      # Force level overrides distance
      still_billboard = LOD.update_level(lod, 10.0)
      assert still_billboard.current_level == :billboard
    end
    
    test "applies LOD bias" do
      lod = LOD.new()
      |> LOD.set_bias(2.0)
      
      # With bias 2.0, distance is halved for LOD calculation
      updated = LOD.update_level(lod, 100.0)  # Effective distance = 50
      assert updated.current_level == :high
    end
  end
  
  describe "AIController component" do
    test "creates AI with behavior type" do
      ai = AIController.new(:aggressive)
      
      assert ai.behavior_type == :aggressive
      assert ai.state == :idle
      assert ai.enabled
    end
    
    test "changes AI state" do
      ai = AIController.new()
      |> AIController.change_state(:patrol)
      
      assert ai.state == :patrol
      assert ai.previous_state == :idle
      assert ai.state_timer == 0.0
    end
    
    test "manages target entity" do
      ai = AIController.new()
      |> AIController.set_target("enemy_123")
      
      assert ai.target_entity == "enemy_123"
      
      cleared = AIController.clear_target(ai)
      assert cleared.target_entity == nil
    end
    
    test "sets and follows patrol route" do
      points = [%{x: 0, y: 0}, %{x: 10, y: 0}, %{x: 10, y: 10}]
      ai = AIController.new()
      |> AIController.set_patrol_route(points)
      
      {point1, ai2} = AIController.next_patrol_point(ai)
      assert point1 == %{x: 0, y: 0}
      
      {point2, ai3} = AIController.next_patrol_point(ai2)
      assert point2 == %{x: 10, y: 0}
      
      # Loops back to start
      {_point3, ai4} = AIController.next_patrol_point(ai3)
      {point4, _} = AIController.next_patrol_point(ai4)
      assert point4 == %{x: 0, y: 0}
    end
    
    test "updates timers and checks decision needs" do
      ai = %AIController{decision_interval: 100.0}
      
      refute AIController.needs_decision?(ai)
      
      updated = AIController.update_timers(ai, 150.0)
      assert AIController.needs_decision?(updated)
      
      reset = AIController.reset_decision_timer(updated)
      refute AIController.needs_decision?(reset)
    end
  end
  
  describe "Behavior component" do
    test "creates behavior tree nodes" do
      tree = Behavior.sequence("root", [
        Behavior.action("move", :move_to_target),
        Behavior.action("attack", :attack_target)
      ])
      
      behavior = Behavior.new(tree)
      
      assert behavior.tree.type == :sequence
      assert length(behavior.tree.children) == 2
    end
    
    test "manages blackboard state" do
      behavior = Behavior.new()
      |> Behavior.set_blackboard(:target, "enemy_1")
      |> Behavior.set_blackboard(:health, 100)
      
      assert Behavior.get_blackboard(behavior, :target) == "enemy_1"
      assert Behavior.get_blackboard(behavior, :health) == 100
      
      cleared = Behavior.clear_blackboard(behavior)
      assert cleared.blackboard == %{}
    end
    
    test "tracks completed actions" do
      behavior = Behavior.new()
      |> Behavior.complete_action(:move)
      |> Behavior.complete_action(:attack)
      
      assert :attack in behavior.completed_actions
      assert :move in behavior.completed_actions
    end
  end
  
  describe "Perception component" do
    test "creates perception with ranges" do
      perception = Perception.new(50.0, 75.0, 10.0)
      
      assert perception.sight_range == 50.0
      assert perception.hearing_range == 75.0
      assert perception.proximity_range == 10.0
    end
    
    test "detects and forgets entities" do
      perception = Perception.new()
      |> Perception.detect_entity("enemy_1", 30.0, :visual, 0.8)
      
      assert Map.has_key?(perception.detected_entities, "enemy_1")
      
      forgotten = Perception.forget_entity(perception, "enemy_1")
      refute Map.has_key?(forgotten.detected_entities, "enemy_1")
    end
    
    test "respects max tracked limit" do
      perception = %Perception{max_tracked: 2}
      |> Perception.detect_entity("e1", 10.0)
      |> Perception.detect_entity("e2", 20.0)
      |> Perception.detect_entity("e3", 5.0)  # Should remove oldest
      
      assert map_size(perception.detected_entities) == 2
    end
    
    test "finds closest and highest threat" do
      perception = Perception.new()
      |> Perception.detect_entity("close", 10.0, :visual, 0.3)
      |> Perception.detect_entity("threat", 50.0, :visual, 0.9)
      
      closest = Perception.get_closest(perception)
      assert closest.id == "close"
      
      threat = Perception.get_highest_threat(perception)
      assert threat.id == "threat"
      
      assert Perception.has_threats?(perception)
    end
    
    test "updates perception with time" do
      perception = %Perception{forget_time: 100.0}
      |> Perception.detect_entity("old", 10.0)
      
      # Update past forget time
      updated = Perception.update(perception, 150.0)
      assert map_size(updated.detected_entities) == 0
    end
  end
end