# 代码地图（func → 行号 索引）

> 自动生成于 2026-10-04。刷新：`python tools/gen_code_map.py`
> ⚠ 用法：**grep 本文件找函数名拿行号，禁止整读本文件**；拿到行号后用 Read 的 offset/limit 只读源码目标段 ±80 行。

> 全项目 214 个脚本 / 69843 行（不含 .uid）
## battle（详细层）

### scripts/battle/ai_communication.gd — 546行 — 31 func
L47 ---- 17号通讯协议v2：开关（单口拦截，默认关=全旁路，行为与旧版逐位一致） ----
L57 signal message_sent
L76 func _process
L88 func set_ai_manager
L92 func set_ball
L96 ---- = ----
L97 ---- 发送消息 ----
L98 ---- = ----
L100 func try_send_message
L125 func can_send
L139 ---- = ----
L140 ---- 17号 协议v2：负载化 ----
L141 ---- = ----
L144 func reload_protocol_switch
L156 func _ensure_protocol_switch
L163 func post_message
L184 func record_v2_message
L202 func _v2_purge_expired
L207 func get_active_messages
L219 func is_type_active
L223 func get_latest_message
L235 func is_enemy_ult_warning_hot
L247 func inject_message
L264 ---- = ----
L265 ---- AI 自动发送逻辑 ----
L266 ---- = ----
L268 func evaluate_ai_messages
L283 func _evaluate_single_ai
L289 ---- 情况1：我看到了持球者没看到的敌人 → 注意防守 ----
L308 ---- 情况2：我在好位置且持球者没看到我 → 传球给我 ----
L327 ---- 情况3：我看到持球者要传球的目标附近有敌人 → 别传球 ----
L350 func _get_carrier_profile
L363 ---- = ----
L364 ---- 消息对AI决策的影响 ----
L365 ---- = ----
L367 func get_team_messages
L375 func get_pass_to_me_bonus
L392 func is_dont_pass_active
L408 func has_pass_to_me
L422 func get_pass_to_me_sender
L440 func has_defend_alert
L453 func has_skill_ready
L466 func get_skill_ready_sender
L483 func has_need_buff
L496 func get_need_buff_sender
L513 func has_buff_on_you
L528 ---- = ----
L529 ---- 记录消息（内部使用） ----
L530 ---- = ----
L532 func record_message
L543 func _pname

### scripts/battle/ai_manager.gd — 2688行 — 86 func
L14 func _get_spirit_ai_manager_script
L82 func _ready
L86 func initialize
L98 func _deferred_init_spirit_ai
L103 func refresh_spirit_ai_skills
L108 func _physics_process
L150 ---- = ----
L151 ---- M5 跳跃反应 ----
L152 ---- = ----
L166 func _update_jump_reaction
L235 func _dodge_roll
L243 ---- = ----
L244 ---- 注册 ----
L245 ---- = ----
L247 func register_player
L283 func _is_valid
L292 func _is_penalized
L300 ---- = ----
L301 ---- 视野感知系统 ----
L302 ---- = ----
L304 func _is_in_field_of_view
L318 func _update_awareness
L347 ---- 视野感知（高精度） ----
L363 ---- 常识感知：队友始终知道存在（低精度，不依赖视野） ----
L384 ---- 近距离必感知（敌人贴脸了还不知道就太假了） ----
L404 func _decay_memory
L420 func _get_known_enemies
L433 func _get_known_teammates
L445 func _find_nearest_visible_enemy
L462 func get_ap_for_player
L469 ---- = ----
L470 ---- 朝向系统 ----
L471 ---- = ----
L473 func _update_facing
L507 func _get_facing_target
L533 ---- = ----
L534 ---- 决策(核心逻辑) ----
L535 ---- = ----
L537 func _decide
L561 ---- 防御接球判定 ----
L571 ---- 通信系统：响应玩家指令 ----
L605 ---- 状态防抖：如果在当前位置附近已到达目标，不要重复切换 ----
L663 ---- = ----
L664 ---- 角色分化行为 ----
L665 ---- = ----
L667 func _decide_off_ball_role
L706 func _decide_teammate_has_ball
L728 func _decide_enemy_has_ball
L739 ---- 防御手：对手在己方半场近距离时上前防守 ----
L753 ---- 非防御手：微动待机，不追玩家（防抽搐） ----
L758 ---- = ----
L763 ---- = ----
L768 func _avoid_enemies
L787 func _get_protect_pos
L815 func _get_assist_pos
L835 func _get_attack_wait_pos
L862 func _should_intercept_for_team
L885 func _get_ball_carrier
L894 func _find_nearest_enemy_to_target
L907 func _decide_carrying
L915 ---- 持球总时间检查 ----
L936 ---- 持球观察期：小幅向侧方移动保持活跃 ----
L945 ---- 观察结束,做决策 ----
L964 ---- 贴中线且看不到任何目标：朝敌方半场盲投 ----
L974 ---- 贴中线且只有传球目标（太近）: 强制投球或远传 ----
L986 ---- 看不到任何敌人且不在边界：前压侦查（不盲投） ----
L996 ---- 17号v2 收端补全（protocol_v2 关=不触发，行为与旧版一致） ----
L1022 ---- 带球目标根据角色差异 ----
L1035 ---- P0 Hysteresis 防抖：当前状态对应的行为需达到 margin 才被顶替 ----
L1061 ---- = ----
L1073 ---- = ----
L1076 func _decide_penalty_move
L1085 ---- ① 持球：效用计算选 PASS 还是 ATTACK ----
L1120 ---- 无球 ----
L1124 ---- ①.5 队友传球优先识别（2026-06-17：修复外场接不到队友传球） ----
L1147 ---- ② 球激活飞向外场→先评估球威胁，再判定接不接 ----
L1167 ---- ③ 球在外场（落地/持球者在外场）→评估接不接 ----
L1180 ---- ④ 无球跑位（球不在外场）→按球权+团队策略 ----
L1185 func _move_to_outer_hold
L1235 ---- = ----
L1237 ---- = ----
L1239 func _evaluate_situation
L1276 func _eval_possession_value
L1303 func _eval_team_state
L1325 func _eval_active_skill_ready
L1349 ---- = ----
L1351 ---- = ----
L1358 func _curve
L1376 func _utility_carrying
L1409 func _utility_catch
L1433 func _eval_ball_threat
L1450 ---- = ----
L1452 ---- = ----
L1455 func _is_ball_heading_to_outer
L1469 func _predict_outer_intercept_pos
L1489 func _is_pos_in_outer
L1497 func _am_i_closest_in_outer
L1512 func _get_ball_owner_team
L1523 func _count_alive_in_inner
L1536 func _nearest_inner_enemy_pos
L1544 ---- = ----
L1545 ---- 行动评分 ----
L1546 ---- = ----
L1548 func _eval_best_pass
L1638 func _eval_shoot
L1677 func _eval_dribble
L1692 ---- = ----
L1699 ---- = ----
L1703 func _calc_separation
L1732 func _calc_wall_slide
L1769 func _wall_size_of
L1782 func _calc_avoid_velocity
L1815 func _apply_steering
L1837 ---- = ----
L1838 ---- 移动执行 ----
L1839 ---- = ----
L1841 func _move
L2039 func _report_stuck
L2055 func is_repeat_stuck
L2063 ---- = ----
L2064 ---- 传球和投球 ----
L2065 ---- = ----
L2067 func _do_pass
L2090 func _do_shoot
L2142 func _try_pickup_ball
L2157 func _get_formation_hold_pos
L2184 func _clamp_to_hold_range
L2194 func _get_current_hold_range
L2209 func _get_idle_drift_pos
L2237 func _am_i_closest_to_pos
L2254 ---- = ----
L2255 ---- 阵型跑位系统 ----
L2256 ---- = ----
L2258 func _get_smart_support_pos
L2309 ---- = ----
L2310 ---- 辅助函数 ----
L2311 ---- = ----
L2313 func _should_enter_catch_state
L2348 ---- = ----
L2359 ---- = ----
L2374 func _predict_ball_landing_simple
L2397 func _ball_in_reachable_half
L2414 func _am_i_closest_to_ball
L2420 ---- 1. 同队职责优先级判定（2026-06-17 加强：按职责分工，不看抢球范围） ----
L2438 ---- 2. 同职责比距离（原逻辑保留） ----
L2452 ---- 3. 对方优势判定（球权倾向对方→放弃前压，转防守站位） ----
L2470 func _find_nearest_enemy
L2515 func _has_visible_enemy_nearby
L2535 func _clamp_to_field
L2542 func _clamp_to_half_field
L2556 func _clamp_forward_to_boundary
L2575 func _force_redecide_if_at_boundary
L2584 func _clamp_to_outer_field
L2590 func _clamp_to_outer_field_impl
L2624 func _clamp_player_position
L2649 func _pname
L2655 ---- = ----
L2656 ---- 公开接口 ----
L2657 ---- = ----
L2659 func update_player_profile
L2673 func refresh_all_speeds
L2683 func get_player_profile

### scripts/battle/ai_profile.gd — 471行 — 6 func
L147 func apply_sandbox_override
L201 func get_role_preset
L349 func apply_difficulty
L403 func apply_weakness
L430 func apply_team_strategy
L452 func get_formation_positions

### scripts/battle/ball.gd — 1570行 — 61 func
L43 func _step_z_lerp
L52 func start_visual_fall
L62 func _can_hit_target_at
L76 func preview_path_hits
L105 func _bounce_off_walls
L203 signal ball_caught
L204 signal ball_hit_player
L205 signal ball_out_of_bounds
L207 signal ball_first_land
L208 signal ball_stopped
L213 func get_visual_radius
L217 func _ready
L264 func _physics_process
L307 ---- M1 弹道物理：z 轴积分（技能接管球跳过——暂时无视物理，高度由技能定义） ----
L314 ---- 追踪球状态（2026-09-19 快照化：全部读球私有快照） ----
L317 ---- 追踪：向目标转向 ----
L336 ---- 回旋：飞到一半距离时返回（触发状态内联为球私有） ----
L381 ---- 距离碰撞检测：补充 body_entered 可能漏检的情况 ----
L384 ---- 检测障碍物碰撞 ----
L387 ---- M2 蓝墙反弹：撞场界夹回反射（墙是场地实体，与 z 弹道/技能豁免无关） ----
L391 ---- 检测出界 ----
L404 func _is_out_of_bounds
L413 func _on_ball_out_of_field
L420 ---- 韧性弹飞球出界：球权回攻击者（弹飞朝防守方深处飞，按半场给=必白送防守方——攻防对称） ----
L442 func _return_to_nearest_team_player
L485 func _on_body_entered
L492 ---- M4 高度窗口：球从头顶飞过不触发命中/接球 ----
L533 ---- 同队队友 → 直接接球,不造成伤害 ----
L538 ---- 幻象：击中只扣幻象体力，球继续飞（不当作击中真身） ----
L546 ---- 对方球员 → 击中造成伤害 ----
L579 ---- AOE范围伤害：以被击中球员为圆心，对范围内敌方球员造成伤害 ----
L600 ---- 待接球姿态：韧性判定决定接球成败（2026-09-11 补回 GD 缺失的接球机制） ----
L608 ---- 状态标记（2026-09-19 快照化：读球私有快照） ----
L612 ---- 被击败 ----
L627 ---- 韧性效果响应 ----
L650 ---- 追踪球：击中即停，球权归受击者 ----
L657 ---- 穿透：球不回攻击者，继续飞行 ----
L662 ---- 普通球：球回到攻击者手上 ----
L670 func _catch_ball
L693 func _traj_end
L701 func _on_ball_stopped
L715 ---- 球落地前，检查附近60px内是否有球员 ----
L747 ---- E7v2 球权分层（吸附本意恢复+攻防对称） ----
L779 func launch
L784 ---- 获取攻击者的发球基础球速 ----
L878 func _get_tag_effect_handler
L893 func _default_ball_mods
L915 func return_to_player
L923 func reset
L945 func _set_idle_visual
L952 func _apply_ball_skill
L967 func _pname
L975 func _create_skill_aura
L984 func _show_skill_aura
L1007 func _clear_skill_aura
L1014 func _process_aura
L1022 func _get_element_color
L1035 func _create_aura_texture
L1057 func set_active_skill
L1063 func cancel_active_skill
L1081 func _is_skill_controlled
L1096 func set_lob_trajectory
L1105 func _step_ballistic_z
L1139 func _get_effective_bounce_e
L1150 func set_bounce_coefficient
L1169 func get_bounce_coefficient
L1175 func _on_collision_with_boundary
L1203 func apply_impulse
L1216 func _check_player_collision_distance
L1259 func _check_obstacle_collision
L1294 func _process_obstacle_stuck
L1345 func _stop_and_return
L1363 func _emit_stop_hooks
L1370 func _get_all_players_array
L1387 func is_ball_visible_to
L1397 func is_stealthed
L1402 func _on_zone_ball_passed
L1417 func _spawn_clones
L1433 func boost_in_flight
L1442 func recall_ball
L1453 func begin_manual_steering
L1465 func manual_steer
L1471 func _sync_basic_ui_visuals
L1488 func steer_space_action
L1498 func _collect_aoe_targets
L1520 func _find_obstacle_manager
L1536 func _get_obstacle_hit_radius
L1545 func _get_match_stats
L1556 func _attacker_element
L1567 func _event_bus

### scripts/battle/battle_hud.gd — 692行 — 21 func
L4 ---- 底部球员面板（玩家方） ----
L7 ---- 顶部计分板下方（对方体力） ----
L42 func _ready
L52 func _process
L64 func _on_player_skills_changed
L71 func setup_players
L109 func _ensure_enemy_markers
L135 func _update_player_skill_icons
L179 func _get_element_color
L192 func _create_skill_toast
L208 func show_skill_toast
L219 func _update_bars
L270 func _get_total_bonuses
L294 ---- = ----
L296 ---- = ----
L298 func _create_score_panel
L328 func _create_enemy_stamina_panel
L379 ---- = ----
L381 ---- = ----
L383 func _create_player_panels
L404 func panel_width_target
L408 func _create_single_panel
L603 ---- = ----
L605 ---- = ----
L607 func _on_time_updated
L614 func _on_score_updated
L618 ---- = ----
L620 ---- = ----
L622 func _create_quick_message_bar
L667 func _on_quick_msg_pressed
L691 func set_comm_system

### scripts/battle/battle_item_granter.gd — 138行 — 9 func
L17 func _ready
L22 func _bus
L27 func _ensure_subscribed
L40 func grant_battle_item
L66 func use_battle_item
L100 func _on_intercept
L115 func _has_item
L120 func _consume_item
L131 func clear_all

### scripts/battle/battle_manager.gd — 2123行 — 87 func
L50 ---- P1方案A：自动模拟模式（headless 验证用，跳过备战面板） ----
L52 ---- 10工单P1：完全体AI观察模式（--fullai）：自动开赛+全AI接管（复用 sim 既有路径），保留 3D 场景供实机观战 ----
L78 func is_input_aiming
L91 func _ready
L92 ---- P1方案A：sim 种子必须最先设（抢在 Godot 自动 randomize() 后重新固化） ----
L140 ---- P1方案A：自动模拟模式启动（种子已在 _ready 开头解析） ----
L156 ---- 事件总线（副系统·E1）：玩法事件六大类，判定点 emit / 响应器订阅 ----
L167 ---- 3D 场景桥接层（USE_3D_SCENE=true 时激活；2D 逻辑零改动，bridge 只读同步） ----
L178 func _parse_sim_args
L201 func _create_field
L222 func _create_wall
L234 func _create_ball
L244 func _setup_input_manager
L272 func _setup_teams
L309 func _create_player
L324 func _assign_initial_ball
L337 func _setup_ui
L362 ---- 信号处理 ----
L364 func _on_player_switch
L372 func _on_throw_requested
L395 func _on_throw_cancelled
L406 func _clear_path_highlights
L414 func _on_catch_entered
L418 func _on_catch_exited
L422 func _on_skill_requested
L428 func _on_skill_cancel_requested
L436 func _on_quick_command
L442 func _on_comm_message_sent
L462 func _show_message_bubble
L474 func _show_opponent_dots
L485 func _update_message_bubbles
L514 func _on_player_defeated
L550 ---- 违规检测与处理 ----
L552 func _check_violations
L587 func _handle_violation
L613 func _schedule_transfer
L630 func _process
L669 func _on_match_paused
L675 func _on_match_resumed
L685 func _on_phase_changed
L742 func _freeze_all_for_half_time
L754 func _show_half_time_prep
L792 func _hide_half_time_prep
L844 ---- 隔离墙管理 ----
L846 func _create_penalty_walls
L854 func _create_penalty_wall
L873 func _build_penalty_enclosure
L908 func _remove_penalty_enclosure
L923 func _ensure_all_penalty_enclosures
L952 func _on_player_transition_completed
L963 ---- 瞄准可视化 ----
L965 func _create_aim_visuals
L983 func _on_aim_info_updated
L1025 func _update_path_highlights
L1049 func _get_all_players
L1058 func _draw_dashed_line
L1090 func _cleanup_old_aim_lines
L1098 func _on_cursor_info_updated
L1128 func _update_all_player_arrows
L1152 func _create_player_arrow
L1160 func _update_player_arrow
L1193 func _update_aim_arrow
L1219 func _create_circle_points
L1228 ---- AI和备战界面 ----
L1230 func _setup_ai_manager
L1272 func _setup_comm_system
L1297 func _setup_preparation_ui
L1355 func _setup_field_physics_manager
L1379 func _on_friction_changed
L1384 func _on_bounciness_changed
L1389 func _setup_summon_manager
L1398 func _setup_item_granter
L1407 func _setup_obstacle_manager
L1420 func _setup_field_zone_manager
L1436 func _setup_illusion_manager
L1446 func _setup_spirit_system
L1461 func _deferred_init_spirit_system
L1510 func _on_skill_effect_finished
L1521 func _on_player_skill_used
L1540 func _show_preparation_ui
L1581 func _on_strategy_changed
L1586 func _on_player_substituted
L1607 func _autofill_team_b
L1642 func _on_spirit_changed
L1674 func _on_prep_match_started
L1730 ---- 中场休息后恢复下半场 ----
L1739 ---- 开场备战后正式开始比赛 ----
L1748 ---- P1方案A：自动模拟模式下创建指标采集器 + 加速 ----
L1757 ---- 个人数据采集器 ----
L1773 func _on_dev_prep_match_started
L1875 func _setup_ai_for_dev_prep
L1907 func _setup_spirit_for_dev_prep
L1940 func _apply_player_data
L1974 func _on_back_to_menu
L1988 func _on_sim_match_ended
L2000 func _dump_event_log
L2024 func _auto_equip_spirits_for_sim
L2037 ---- 结算界面 ----
L2039 func _show_result_ui_delayed
L2046 func _show_result_ui
L2085 func _on_result_confirmed
L2097 ---- 中途退出 ----
L2099 func _unhandled_input
L2107 func _forfeit_match

### scripts/battle/drain_wall.gd — 50行 — 3 func
L16 func setup_drain
L23 func _physics_process
L48 func consume_frame

### scripts/battle/enemy_status_marker.gd — 105行 — 8 func
L35 func should_mark
L49 func _ready
L55 func bind_enemy
L60 func _on_lights_changed
L79 func _on_toggle_changed
L84 func _icon_for
L90 func _process
L98 func _draw

### scripts/battle/field_effect_zone.gd — 510行 — 19 func
L11 signal zone_expired
L48 signal zone_ball_passed
L52 signal entity_entered_path
L53 signal entity_exited_path
L54 signal path_depleted
L96 func setup
L157 func _parse_zone_type
L182 func _build_visual
L244 func _update_visual
L259 func _process
L293 func _process_danger_tick
L309 func _process_heal_tick
L322 func _process_energy_path_tick
L339 func _deplete
L349 func contains_point
L357 func direction
L364 func _on_body_entered
L393 func _check_initial_overlaps
L407 func _on_body_exited
L431 func _apply_effect
L460 func _remove_effect
L481 func _expire
L497 func force_remove
L502 func get_zone_info

### scripts/battle/field_physics_manager.gd — 299行 — 15 func
L50 signal friction_changed
L53 signal bounciness_changed
L56 signal restored_to_defaults
L61 func _ready
L75 func set_friction
L120 func add_terra_zone
L125 func get_friction_at
L133 func get_friction
L147 func restore_friction
L168 func set_bounciness
L194 func get_bounciness
L207 func restore_bounciness
L227 func restore_all_defaults
L246 func _check_friction_restore
L256 func _cleanup_terra_zones
L270 func get_status_info
L282 func print_status
L288 func get_remaining_restore_time

### scripts/battle/field_zone.gd — 655行 — 45 func
L57 signal player_violated
L58 signal player_transition_completed
L63 func _ready
L67 func _process
L86 ---- 区域判定 ----
L88 func get_zone_at
L98 func is_in_playable_area
L102 func check_boundary_violation
L107 func check_midline_violation
L125 func check_field_boundary_violation
L144 func check_zone_violation
L163 func start_field_transition
L184 func _calc_non_overlapping_pos
L192 func is_player_transitioning
L196 ---- 中心点查询 ----
L198 func get_inner_center
L201 func get_outer_center
L204 func get_left_outer_center
L207 func get_right_outer_center
L210 func get_opponent_outer_center
L216 ---- 包含检测 ----
L218 func _is_in_inner
L221 func _is_in_outer
L226 ---- 视觉构建 ----
L228 func _build_visual_field
L272 func _draw_zone
L280 func _draw_border_rect
L313 func _draw_outer_field_border
L391 func _label
L400 func _draw_center_circle
L421 ---- 工具 ----
L423 func _in_rect
L426 func _rect_center
L430 ---- = ----
L431 ---- 场地知识库（13号工单：技能AI与球员AI共用的场地认知共享层） ----
L432 ---- = ----
L460 func knowledge_zone_of
L485 func _knowledge_lines
L522 func knowledge_dist_to_line
L531 func knowledge_would_cross_line
L540 func knowledge_outer_gate_segment
L546 func knowledge_outer_gate_point
L552 func knowledge_own_gate_point
L557 func knowledge_enemy_gate_point
L562 func knowledge_nearest_gate
L572 func knowledge_goal_area_point
L583 func knowledge_side_anchor
L596 func knowledge_enemy_side_anchor
L603 func knowledge_own_line_inner_point
L612 func knowledge_would_violate
L625 func knowledge_rescue_rule_active
L629 func _k_in_rect
L634 func _k_in_outer_static
L638 func _k_seg_closest
L647 func _k_seg_intersect

### scripts/battle/field_zone_manager.gd — 238行 — 21 func
L15 signal zone_ball_passed
L17 signal entity_entered_path
L18 signal entity_exited_path
L19 signal path_depleted
L23 func _ready
L36 func spawn_zone_at
L41 func create_zone
L98 func _on_zone_ball_passed
L103 func _on_entity_entered_path
L107 func _on_entity_exited_path
L111 func _on_path_depleted
L116 func is_in_energy_path
L125 func get_perception_scale_at
L142 func remove_zone
L149 func remove_zone_by_id
L158 func clear_all_zones
L169 func get_zone_count
L174 func get_all_zones
L183 func get_zone_at_position
L199 func start_placing
L205 func start_zone_clearing
L211 func cancel_operation
L217 func is_operating
L226 func _cleanup
L234 func _on_zone_expired

### scripts/battle/field_zone_placer.gd — 416行 — 26 func
L36 signal operation_finished
L41 func start_placing
L56 func _create_preview
L118 func start_clearing
L129 func _ready
L133 func _process
L143 func _process_placing
L178 func _is_path_mode
L182 func _process_clearing
L198 func _input
L216 func _on_left_click
L226 func _place_zone
L263 func path_release_points
L271 func _clear_step
L297 func _on_right_click
L306 func cancel_operation
L312 func is_operating
L316 func _cancel_internal
L326 func _finish_operation
L334 func _create_highlight
L354 func _clear_highlights
L361 func _remove_preview
L369 func _get_mouse_position
L379 func _get_manager
L386 func _parse_zone_type
L402 func _get_zone_colors
L414 func _get_zone_name

### scripts/battle/illusion.gd — 286行 — 14 func
L60 signal illusion_expired
L65 func setup
L101 func _build_visual
L137 func _physics_process
L169 func _mirror_source
L178 func _ai_move
L194 func take_damage
L218 func is_status_active
L225 func _expire
L234 func force_remove
L239 func get_illusion_info
L248 func add_buff
L261 func remove_buff
L265 func _get_effective_value
L278 func _tick_buffs

### scripts/battle/illusion_manager.gd — 153行 — 14 func
L16 func _ready
L27 func create_illusion
L58 func remove_illusion
L64 func remove_illusion_by_id
L75 func clear_all_illusions
L87 func get_illusion_count
L92 func get_all_illusions
L101 func get_illusion_at_position
L117 func start_placing
L124 func start_clearing
L129 func cancel_operation
L134 func is_operating
L142 func _cleanup
L150 func _on_illusion_expired

### scripts/battle/illusion_placer.gd — 446行 — 31 func
L51 signal operation_finished
L56 func start_placing
L81 func _create_circle_preview
L110 func _create_sector_preview
L122 func start_clearing
L133 func _ready
L137 func _process
L150 func _process_placing_any
L160 func _process_placing_near
L179 func _process_clearing
L197 func _input
L213 func _on_left_click
L224 func _on_right_click
L231 func _place_any
L246 func _place_near
L275 func _clear_step
L300 func cancel_operation
L306 func is_operating
L310 func _cancel_internal
L323 func _finish_operation
L331 func _update_player_highlight
L345 func _rebuild_sector
L364 func _make_polygon
L382 func _create_clear_highlight
L393 func _clear_highlights
L400 func _remove_preview
L406 func _remove_sector
L412 func _remove_player_highlight
L420 func _circle_points
L428 func _is_in_field
L432 func _get_mouse_position
L442 func _get_manager

### scripts/battle/input_manager.gd — 717行 — 34 func
L42 signal player_switch_requested
L43 signal throw_requested
L44 signal throw_cancelled
L45 signal catch_state_entered
L46 signal catch_state_exited
L47 signal skill_requested
L48 signal quick_command_requested
L49 signal aim_info_updated
L50 signal cursor_info_updated
L51 signal player_facing_updated
L52 signal skill_cancel_requested
L55 func _input
L61 ---- 球员切换（点击头像/Tab） ----
L99 ---- 鼠标操作 ----
L124 func compute_fp_move
L134 func toggle_fp_mode
L146 func _on_left_click_press
L175 func _on_left_click_release
L239 func _on_right_click_press
L263 func _on_right_click_release
L272 func _cycle_player
L283 func _tab_skill_state_switch
L300 func is_skill_control_active
L311 func _find_drag_candidate
L341 func _set_drag_ring
L354 func update_aim_from_mouse
L364 func inject_steer_to_ball
L372 func compose_steer_direction
L379 func _route_space_to_skill
L388 func set_controlled_player
L398 func get_aim_info
L418 func _process
L489 func get_movement_direction
L503 func _init_skill_state_manager
L527 func refresh_controlled_skills
L531 func _handle_skill_key_press
L552 func _handle_skill_cancel
L565 func _on_skill_activated
L605 func _on_skill_cancelled
L614 func _on_skill_released
L625 func _release_active_skill
L634 func cleanup
L642 func _any_placer_operating
L655 func _show_skill_toast
L675 func _get_skill_data
L688 func _get_tag_category
L698 func _load_tags_registry

### scripts/battle/input_manager_old.gd — 195行 — 10 func
L20 signal player_switch_requested
L21 signal throw_requested
L22 signal throw_cancelled
L23 signal catch_state_entered
L24 signal catch_state_exited
L25 signal skill_requested
L26 signal quick_command_requested
L27 signal aim_info_updated
L30 func _input
L34 ---- 球员切换（点击头像/Tab） ----
L58 ---- 鼠标操作 ----
L72 func _on_left_click_press
L84 func _on_left_click_release
L106 func _on_right_click_press
L120 func _on_right_click_release
L129 func _cycle_player
L138 func set_controlled_player
L146 func get_aim_info
L166 func _process
L186 func get_movement_direction

### scripts/battle/knockback_physics.gd — 482行 — 10 func
L38 func calculate_distance
L94 func calculate_initial_velocity
L127 func calculate_current_velocity
L152 func calculate_knockback
L206 func calculate_required_friction
L247 func calculate_required_skill_multiplier
L275 func format_knockback_info
L302 func generate_distance_samples
L361 func generate_friction_samples
L439 func generate_full_samples

### scripts/battle/match_player_stats.gd — 194行 — 18 func
L29 func to_dict
L53 func start_recording
L59 func stop_recording
L64 func is_recording
L69 func register_player
L80 func get_stats
L85 func get_all_stats
L90 func get_team_stats
L100 func get_report
L109 func print_report
L121 ---- 事件上报接口（由 player.gd / ball.gd 调用） ----
L124 func report_defeat
L137 func report_damage_dealt
L146 func report_damage_taken
L155 func report_ball_caught
L164 func report_ball_intercepted
L173 func report_skill_used
L182 func report_skill_hit
L191 func record_final_stamina

### scripts/battle/match_stats.gd — 187行 — 11 func
L18 ---- 球权流转 ----
L23 ---- 命中/伤害 ----
L27 ---- 失误 ----
L30 ---- ai_manager 上报 ----
L36 ---- 比赛结果 ----
L47 func start_recording
L63 func stop_recording
L68 func _reset_counters
L81 ---- = ----
L82 ---- 球信号回调 ----
L83 ---- = ----
L85 func _on_ball_caught
L99 func _on_ball_hit
L106 func _on_ball_out
L112 ---- = ----
L113 ---- ai_manager 上报接口 ----
L114 ---- = ----
L117 func record_stuck
L125 func record_state_change
L133 func set_final_score
L138 ---- = ----
L139 ---- 报告输出 ----
L140 ---- = ----
L143 func get_report
L170 func print_report

### scripts/battle/obstacle.gd — 314行 — 15 func
L31 signal obstacle_destroyed
L32 signal obstacle_expired
L37 func setup
L59 func _create_collision
L107 func _build_crescent_points
L124 func _create_visual
L174 func _create_border
L207 func _create_hp_bar
L228 func _create_duration_timer
L242 func consume_frame
L261 func _update_hp_bar
L281 func _destroy
L287 func _on_duration_expired
L293 func remove
L300 func is_alive
L305 func get_hp_ratio
L312 func get_hit_radius

### scripts/battle/obstacle_manager.gd — 249行 — 19 func
L20 func _ready
L33 func create_obstacle
L92 signal player_shield_spawned
L93 signal player_shield_removed
L96 func create_player_shield
L109 func get_player_shield
L118 func remove_obstacle
L123 func remove_obstacles
L130 func clear_all_obstacles
L139 func clear_obstacles_by_skill
L149 func get_obstacle_at_position
L172 func get_all_obstacles
L182 func get_obstacle_count
L190 func start_placing
L196 func start_clearing
L202 func cancel_operation
L208 func is_operating
L217 func _remove_obstacle
L225 func _obstacles_cleanup
L234 func _on_obstacle_destroyed
L243 func _on_obstacle_expired

### scripts/battle/obstacle_placer.gd — 383行 — 22 func
L30 signal operation_finished
L35 func start_placing
L46 func _create_preview
L116 func _build_crescent_points
L133 func start_clearing
L146 func _ready
L150 func _process
L160 func _process_placing
L175 func _process_clearing
L196 func _input
L214 func _on_left_click
L225 func _place_obstacle
L254 func _clear_step
L284 func _on_right_click
L295 func cancel_operation
L302 func is_operating
L307 func _cancel_internal
L319 func _finish_operation
L328 func _create_highlight
L350 func _clear_highlights
L358 func _remove_preview
L367 func _get_mouse_position
L378 func _get_manager

### scripts/battle/physics_test.gd — 281行 — 14 func
L24 func _ready
L32 func _process
L44 func _input
L57 func start_test
L71 func reset_test
L87 func print_status
L110 func _run_test_phase
L135 func _test_initialization
L172 func _test_friction
L200 func _test_bounciness
L236 func _test_knockback
L251 func _next_phase
L263 func set_friction
L274 func restore_defaults

### scripts/battle/player.gd — 2469行 — 125 func
L34 signal defeated
L249 ---- 2.5D 3D模型挂载 ----
L276 func _get_model_path
L309 func _ready
L318 func initialize
L351 func _recalculate_all_bonuses
L406 func refresh_bonuses
L411 func _on_phase_changed
L419 func get_base_ball_speed
L440 func _setup_visuals
L462 func _setup_2d_avatar
L492 func _setup_3d_model
L538 func _setup_subviewport_world
L560 func _load_main_glb
L625 func _find_skeleton3d
L636 func _hide_mixamo_helpers
L645 func _rename_default_anim_to
L670 func _find_animation_player
L681 func _merge_animation_libraries
L744 func _update_3d_animation
L781 func _resolve_anim_name
L799 func _update_3d_facing
L809 func play_3d_action
L822 func get_3d_debug_info
L849 func set_view_mode
L879 func _teardown_visuals
L897 func _make_circle_style
L904 func _get_display_number
L910 func _clamp_to_field
L922 func _physics_process
L1069 func try_jump
L1088 func can_jump
L1097 func is_airborne
L1102 func _regen_endurance
L1109 func get_hit_z_range
L1114 func get_ball_origin_z
L1119 func set_path_highlight
L1137 func _step_jump_z
L1150 func _interrupt_jump
L1157 func _update_jump_visual
L1182 func take_damage
L1238 ---- 待接球: 韧性系统生效 ----
L1271 ---- 非待接球: 新体力 = 当前体力 + 防御抗力 - 攻击 ----
L1315 func _get_resilience_decay_rate
L1331 func _get_stagger_by_resilience
L1348 func _roll_resilience_effect
L1383 func _get_phase2_knockback_chance
L1409 func _get_field_friction
L1448 func _apply_knockback
L1499 func _on_defeated
L1539 func set_penalized
L1555 func enter_catch_state
L1563 func exit_catch_state
L1571 func set_carrying_ball
L1584 func can_be_scored_against
L1589 func use_skill
L1643 signal skill_used
L1644 signal facing_direction_changed
L1645 signal message_bubble_requested
L1648 func start_sprint
L1657 func show_message_bubble
L1667 func set_active_skill
L1686 func clear_active_skill
L1696 func get_active_skill_id
L1701 func _get_skill_visual_type
L1725 func _update_skill_visuals
L1732 func _update_player_outline
L1743 func _update_field_indicator
L1762 func _update_ball_skill_aura
L1775 func _clear_ball_skill_aura
L1782 func _get_ball_node
L1795 func use_skill_by_id
L1805 func get_equipped_skills
L1815 func get_visual_radius
L1821 func get_skill_cooldown_ratio
L1833 func load_spirit_by_element
L1850 func equip_spirit
L1864 func unequip_spirit
L1886 signal mark_changed
L1889 signal status_lights_changed
L1890 signal toggle_changed
L1892 signal toggle_auto_closed
L1896 func apply_mark
L1904 func drain_all_marks
L1914 func receive_mark
L1926 func get_mark_count
L1930 func clear_mark
L1935 func _tick_marks
L1947 func open_toggle
L1959 func close_toggle
L1968 func _process_toggles
L1983 func begin_carry_push
L1989 func _process_carry_push
L2003 signal charge_stock_empty
L2019 func get_status_lights_view
L2026 func is_status_active
L2031 func turn_on_light
L2069 func turn_off_light
L2078 func get_defense_resist
L2083 func heal
L2093 func drain_stamina
L2104 func get_charge_stock
L2111 func consume_charge
L2124 func get_energy_share_pct
L2131 func mark_lights_break_on_hit
L2142 func _expire_lights_on_hit
L2151 func turn_off_lights_by_type
L2157 func _tick_status_lights
L2180 func _update_state_indicator
L2202 func add_tick_effect
L2217 func remove_tick_effect
L2222 func has_tick_effect
L2227 func get_total_tick_rate
L2236 func _tick_all_timers
L2255 func _process_tick_effects
L2294 func add_skill_cost_mult
L2299 func get_skill_cost_mult
L2307 func add_skill_cd_mult
L2312 func get_skill_cd_mult
L2320 func add_next_skill_mult
L2325 func get_and_consume_next_skill_mult
L2342 func remove_skill_cost_mult
L2346 func remove_skill_cd_mult
L2350 func add_skill_bonus_uses
L2357 func get_skill_bonus_uses
L2361 func _process_discount_cards
L2367 func _tick_mult_dict
L2380 func add_buff
L2397 func remove_buff
L2401 func has_buff
L2405 func get_buff_count
L2409 func _get_effective_value
L2422 func _tick_buffs
L2439 func teleport_to
L2444 func return_to_previous
L2452 func _get_match_stats
L2464 func _emit_catch_stance

### scripts/battle/player_shield.gd — 92行 — 9 func
L9 signal shield_state_changed
L20 func setup_shield
L32 func _process
L41 func _follow_caster
L52 func get_shield_hp
L57 func on_ball_hit
L67 func consume_frame
L79 func _signal_broken
L85 func _destroy
L90 func _on_duration_expired

### scripts/battle/shield_visual_2d.gd — 68行 — 5 func
L14 func setup
L24 func _refresh_from_host
L36 func _on_shield_state_changed
L40 func _process
L45 func _draw

### scripts/battle/spirit_ai/ai_input_source.gd — 331行 — 11 func
L32 func generate_operation_intent
L60 func apply_operation
L94 func attach
L101 func detach
L114 func tick_activation
L166 func _midfly_intent_by_policy
L213 func build_default_ctx
L236 ---- 私有工具（零感知直连，全部从 ctx 取；平局取遍历序首个=确定性） ----
L239 func _compute_steer_aim
L262 func _compute_midfly_intent
L312 func _valid_enemies
L323 func _nearest_node_to

### scripts/battle/spirit_ai/event_hooks.gd — 140行 — 10 func
L31 func set_cycle
L35 func get_cycle
L40 func attach
L50 func detach
L58 func _on_event
L73 func is_reaction_hot
L86 func pending_count
L95 func clear
L100 ---- 波E复制族：技能释放快照口（生存窗口机动领域=事件钩子域；向后兼容只增不改） ----
L104 func record_skill_cast
L115 func get_recent_enemy_cast
L135 ---- 集成窗口接线说明（本波不接线，只读知悉） ----

### scripts/battle/spirit_ai/primitive_registry.gd — 156行 — 11 func
L27 func get_descriptor
L40 func get_descriptor_entry
L51 func is_wave_enabled
L63 func is_event_hook_priority
L69 func reload_switches
L75 func get_extra_flag
L82 func get_switches_state
L91 ---- 内部实现 ----
L93 func _ensure_aggregated
L100 func _ensure_switches
L108 func _aggregate
L134 func _load_switches

### scripts/battle/spirit_ai/primitives_a.gd — 163行 — 8 func
L18 func get_descriptors
L27 func _load_table
L59 func timing_gate
L118 func compute_value
L130 func resolve_target_mode
L134 ---- 私有工具（零感知直连，全部从 ctx 取） ----
L136 func _player_holds_ball
L143 func _nearest_enemy_dist
L156 func _ratio_of

### scripts/battle/spirit_ai/primitives_b.gd — 231行 — 9 func
L26 func get_descriptors
L35 func _load_table
L68 func timing_gate
L170 func _is_in_outer
L181 func compute_value
L195 func resolve_target_mode
L199 ---- 私有工具（零感知直连，全部从 ctx 取） ----
L201 func _player_holds_ball
L208 func _nearest_enemy_dist
L221 func _ally_ratio

### scripts/battle/spirit_ai/primitives_c.gd — 188行 — 10 func
L28 func get_descriptors
L40 func _parse_descriptors
L57 func timing_gate
L121 func compute_value
L132 func resolve_target_mode
L137 ---- 私有工具（只消费 ctx 与其携带的节点引用，禁直连管理器原始感知） ----
L140 func _get_player
L147 func _get_visible_enemies
L160 func _has_visible_carrier
L169 func _nearest_enemy_distance
L179 func _ratio_of

### scripts/battle/spirit_ai/primitives_d.gd — 300行 — 13 func
L31 func get_descriptors
L43 func _parse_descriptors
L61 func timing_gate
L123 func compute_value
L134 func resolve_target_mode
L142 func select_field_position
L227 ---- 私有工具（只消费 ctx 与其携带的节点引用，禁直连管理器原始感知） ----
L230 func _get_player
L237 func _get_visible_enemies
L250 func _has_visible_carrier
L257 func _pick_carrier
L267 func _nearest_enemy_distance
L276 func _pick_closest_enemy
L288 func _pick_aoe_enemy

### scripts/battle/spirit_ai/primitives_e.gd — 180行 — 8 func
L27 func get_descriptors
L36 func _load_table
L69 func timing_gate
L130 func compute_value
L144 func resolve_target_mode
L148 ---- 私有工具（零感知直连，全部从 ctx 取） ----
L150 func _player_holds_ball
L157 func _nearest_enemy_dist
L170 func _ally_ratio

### scripts/battle/spirit_ai/primitives_f.gd — 180行 — 8 func
L27 func get_descriptors
L36 func _load_table
L69 func timing_gate
L130 func compute_value
L144 func resolve_target_mode
L148 ---- 私有工具（零感知直连，全部从 ctx 取） ----
L150 func _player_holds_ball
L157 func _nearest_enemy_dist
L170 func _ally_ratio

### scripts/battle/spirit_ai_manager.gd — 1966行 — 80 func
L64 func _ensure_catch_hook
L76 func _on_ball_caught_hook
L94 func initialize
L104 func _load_element_counters
L119 func register_player
L137 func refresh_all_skills_analysis
L153 func _cast_stats_register
L160 func _cast_stats_note
L179 func _cast_stats_count
L191 func _cast_stats_hookup
L198 func _print_cast_stats
L232 func _analyze_player_attributes
L279 func _analyze_skills_for_player
L297 func _analyze_skill_combinations
L314 func _detect_combo_type
L334 func _get_combo_bonus
L344 func _analyze_single_skill
L366 func _compute_synergy_level
L412 func _compute_synergy_bonus
L424 func _normalize_tags
L429 func _extract_raw_tags
L442 func _map_tags_to_categories
L472 func _get_tag_category
L488 func _extract_values_from_tag_params
L500 func _compute_base_value
L560 func _compute_ball_value
L601 func _compute_player_value
L652 func _compute_field_value
L700 func _determine_intents
L747 func _compute_tag_intents
L832 func _get_primary_intent
L841 func _physics_process
L874 func _is_valid
L887 func _decide_skill
L953 func _deterministic_dice
L960 func _player_key_v
L963 func _player_key
L966 func _select_skill_with_softmax
L998 func _should_think_about_skills
L1025 func _get_available_skills
L1046 func _on_skill_used_for_hooks
L1056 func get_decision_dump
L1061 func _record_decision_dump
L1084 func _setup_event_hooks
L1095 func _attach_ai_input_source
L1111 func _query_primitive
L1124 func _evaluate_primitive_gates
L1146 func _build_primitive_ctx
L1229 func _has_energy_blocked_burst
L1250 func _compute_skill_score
L1269 func _compute_team_factor
L1291 func _get_team_weaknesses
L1328 func _compute_combo_factor
L1344 func _compute_element_factor
L1369 func _compute_communication_factor
L1389 ---- 17号v2 消费（protocol_v2 关=两查询恒 false，本段恒不触发） ----
L1402 func _compute_time_factor
L1427 func _should_use_energy
L1449 func _compute_situation_factor
L1456 func _compute_numbers_factor
L1493 func _compute_possession_factor
L1526 func _compute_score_factor
L1554 func _compute_intent_match
L1568 func _compute_stamina_factor
L1602 func _select_player_target
L1620 func _select_support_target
L1653 func _select_attack_target
L1702 func _get_team_members
L1712 func _get_enemies
L1722 func _select_field_position
L1758 func _select_wall_position
L1780 func _select_aoe_position
L1810 func _select_area_position
L1819 func _get_our_goal_position
L1825 func _get_enemy_goal_position
L1831 func _get_enemy_ball_holder
L1838 func _execute_skill
L1887 func _send_skill_message
L1927 func _comm_v2_post
L1936 func _try_send_need_buff
L1959 func _decide_mistake_type

### scripts/battle/status_icon_bar.gd — 243行 — 19 func
L36 func _ready
L43 func bind_player
L61 func set_entry
L70 func remove_entry
L75 func get_entry_keys
L81 func connect_shield_source
L90 func _on_shield_spawned
L100 func _on_shield_removed
L105 func _on_shield_state_changed
L110 func _update_shield_entry
L126 func get_visible_count
L134 func _on_lights_changed
L152 func set_entry_raw
L166 func _on_mark_changed
L178 func _process
L191 func _on_toggle_changed
L200 func _queue_redraw
L204 func _draw
L219 func _draw_one


## battle3d（详细层）

### scripts/battle3d/battle3d_const.gd — 138行 — 3 func
L60 func _model_num
L128 func game2d_to_3d
L135 func facing_to_rotation_y

### scripts/battle3d/battle_arena_3d_bridge.gd — 786行 — 37 func
L52 func setup
L82 func _spawn_aim_cursor
L100 func set_aim_cursor
L113 func _sync_fp_mode
L153 func _show_fp_crosshair
L168 func _set_fp_own_proxy_visible
L177 func _setup_fx_adapter
L184 func _setup_parity_check
L189 func _build_display
L201 func _build_world
L245 func _spawn_field_model
L258 func _spawn_player_proxies
L274 func _spawn_ball_proxy
L284 func _apply_field_materials
L307 func _make_mat
L314 func _apply_materials_recursive
L333 func _process
L364 func _on_shield_spawned_3d
L377 func _sync_shields
L393 func _sync_obstacles
L429 func _sync_zones
L466 func _sync_zone_preview
L499 func _sync_summons
L522 func _on_summon_spawned_3d
L546 func _on_summon_despawned_3d
L557 func _check_roster_rebuild
L598 func _parity_tick
L612 func _attach_name_label
L628 func _attach_enemy_marker
L646 func input_mgr_is_controlled
L649 func _sync_players
L673 func _sync_ball
L702 func _sync_camera
L713 func _on_battle_visuals_changed
L723 func _auto_capture_deferred
L735 func _hide_2d_placeholders
L759 func _input

### scripts/battle3d/rules/field_rules_3d.gd — 72行 — 6 func
L31 func _in_rect
L35 func is_in_inner
L39 func is_in_left_outer
L44 func is_in_right_outer
L50 func is_in_blue_boundary
L56 func check_violation

### scripts/battle3d/visual/ball_proxy_3d_v2.gd — 137行 — 10 func
L15 func setup
L46 func set_stealth
L58 func _apply_stealth_to_mesh
L81 func set_flight
L88 func set_carried
L95 func set_idle
L100 func is_mesh_ok
L105 func _process
L114 func _fix_ball_pbr
L134 func _hide_mixamo_helpers

### scripts/battle3d/visual/camera_3d_controller.gd — 92行 — 7 func
L25 func setup
L32 func set_mode
L63 func next_mode
L69 func get_mode_name
L72 func _process
L78 func _update_follow
L86 func _update_fp

### scripts/battle3d/visual/enemy_marker_3d.gd — 66行 — 3 func
L13 func setup
L34 func _on_mark_changed
L42 func _rebuild

### scripts/battle3d/visual/magic_ball_visual_3d.gd — 114行 — 7 func
L26 func setup
L32 func _build_ball
L63 func _process
L74 func _refresh
L80 func _ring_color
L98 func sync_from_2d
L106 func scatter_positions

### scripts/battle3d/visual/obstacle_visual_3d.gd — 111行 — 4 func
L15 func setup
L87 func _process
L91 func _refresh
L109 func sync_from_2d

### scripts/battle3d/visual/operator_feedback_3d.gd — 92行 — 7 func
L19 func _ready
L24 func show_aim_preview
L40 func update_aim_preview_dir
L46 func hide_aim_preview
L52 func show_target_ring
L64 func clear_target_ring
L70 func _ensure_aim_root

### scripts/battle3d/visual/player_proxy_3d.gd — 593行 — 31 func
L31 func setup
L42 ---- ModelSlot（唯一缩放控制点，铁律 scale=70） ----
L48 ---- 0. GLB 外观模式（无专属动作 FBX 的角色：用专属 base.glb 的正确网格/材质，静止姿势） ----
L90 ---- 1. 加载专属 idle 媒势 FBX（带骨骼 mesh） ----
L123 ---- 2. 手动加载 PBR 贴图应用到 FBX mesh ----
L128 ---- 3. AnimationPlayer：深拷贝断共享 → idle 重命名 → 剥 Root Motion ----
L147 ---- 4. 根骨骼节点（运行时强制重置位置，杀 Root Motion 漂移） ----
L150 ---- 5. 队伍色脚下环 + 投球手挂接点 ----
L158 ---- 6. 剔除模型内嵌光源（部分 Idle.fbx 带制作残留灯节点） ----
L170 func _strip_embedded_lights
L176 func _build_ring_only
L195 func _play_initial_idle
L213 func sync_from_2d
L225 func play_action
L233 func get_hand_proxy
L237 func get_cup_center_global
L246 func _build_cup_anchor
L328 func _hand_offset_for
L331 func get_anim_player
L334 func get_anim_names
L344 func is_mesh_ok
L347 func is_anim_playing
L350 func get_current_anim
L354 func set_defeated_visual
L364 func _physics_process
L375 func _force_reset_root_bones
L381 func _reset_positions_in
L391 func _on_action_finished
L395 func play_anim_on
L401 func play_anim
L406 func _hide_mixamo_helpers
L413 func _apply_pbr_textures
L447 func _deep_copy_anim_library
L460 func _rename_default_anim_to
L476 func _merge_shared_animations
L512 func _get_shared_anim_scene
L525 func _strip_root_motion
L570 func _find_animation_player
L580 func _find_root_bone_node

### scripts/battle3d/visual/shark_visual_3d.gd — 96行 — 6 func
L27 func setup
L35 func _build_body
L59 func _add_box
L70 func _process
L75 func _refresh
L94 func sync_from_2d

### scripts/battle3d/visual/shield_visual_3d.gd — 67行 — 5 func
L14 func setup
L36 func _process
L40 func _refresh
L59 func _on_shield_state_changed
L65 func sync_from_2d

### scripts/battle3d/visual/skill_fx_3d_adapter.gd — 147行 — 9 func
L29 func setup
L37 func _load_tag_types
L61 func _connect_signals
L75 func _on_any_skill_triggered
L120 func _on_ball_caught
L128 func _on_ball_hit
L131 func _clear_ball_outline
L136 func _clear_caster
L144 func clear_all

### scripts/battle3d/visual/skill_outline_3d.gd — 55行 — 4 func
L12 func make_ring
L28 func make_strip
L42 func _make_material
L52 func pulse

### scripts/battle3d/visual/zone_visual_3d.gd — 101行 — 6 func
L16 func setup
L49 func _add_border_box
L62 func _make_label
L75 func _process
L79 func _refresh
L99 func sync_from_2d


## core（详细层）

### scripts/core/data_manager.gd — 151行 — 16 func
L11 signal data_loaded
L14 func _ready
L18 func load_all_data
L29 func reload_all
L33 func _load_json_raw
L53 func _load_json_array
L64 func _load_json_dict
L71 func _load_spirits_skills
L83 func _load_spirits_array
L95 ---- 查询方法 ----
L97 func get_character_by_id
L104 func get_spirit_by_id
L111 func get_skills_for_spirit
L115 func get_skill_by_id
L122 func _load_tags
L134 func get_tag_by_id
L141 func get_skills_by_tag
L145 func get_counter_multiplier

### scripts/core/game_manager.gd — 185行 — 14 func
L28 func get_first_half_duration
L31 func get_second_half_duration
L34 func get_half_time_duration
L59 signal phase_changed
L60 signal match_time_updated
L61 signal score_updated
L62 signal match_ended
L63 signal match_paused
L64 signal match_resumed
L67 func _process
L80 func start_match
L92 func _advance_phase
L109 func _set_phase
L115 func add_score
L128 func check_all_defeated
L138 func _check_defeat_condition
L151 func pause_match
L159 func resume_match
L167 func _determine_result
L177 func freeze_all

### scripts/core/player_save_manager.gd — 596行 — 42 func
L36 signal save_loaded
L37 signal save_saved
L38 signal currency_changed
L41 func _ready
L46 func _ensure_save_dir
L51 func _get_save_path
L55 func _get_backup_path
L59 func has_save
L63 func load_slot
L106 func get_team_talent_tree
L109 func save_team_talent_tree
L115 func save_slot
L120 func _save_to_file
L132 func _backup_corrupted
L141 func _create_default_save
L192 func _migrate_save
L229 func is_dev_mode
L233 func get_currency
L238 func set_currency
L246 func add_currency
L258 func spend_currency
L272 func has_character
L279 func unlock_character
L289 func get_unlocked_characters
L301 func get_field_level
L306 func set_field_level
L313 func get_character_train
L332 func set_character_train
L341 func set_training_bonus
L347 func get_data
L354 func set_active_food
L362 func get_active_food
L373 func get_total_stat
L389 func get_equipped
L403 func get_equipped_item
L412 func get_equipped_durability
L421 func set_equipped_durability
L438 func repair_all_equipment_max
L454 func get_backpack_item_durability
L463 func get_all_equipped
L469 func clear_all_equipment
L485 func equip_item
L518 func unequip_item
L524 func reduce_equipment_durability
L562 func get_equipment_bonuses


## dev_tools（摘要层）

- scripts/dev_tools/dev_account_panel.gd — 916行 — 29 func
- scripts/dev_tools/dev_data_sync.gd — 528行 — 33 func
- scripts/dev_tools/dev_element_counter_editor.gd — 241行 — 11 func
- scripts/dev_tools/dev_equipment_panel.gd — 752行 — 20 func
- scripts/dev_tools/dev_food_panel.gd — 717行 — 21 func
- scripts/dev_tools/dev_growth_panel.gd — 389行 — 14 func
- scripts/dev_tools/dev_player_panel.gd — 589行 — 18 func
- scripts/dev_tools/dev_reward_panel.gd — 164行 — 8 func
- scripts/dev_tools/dev_settings_main.gd — 196行 — 12 func
- scripts/dev_tools/dev_spirit_panel.gd — 1683行 — 36 func
- scripts/dev_tools/dev_talent_tree_editor.gd — 960行 — 43 func
- scripts/dev_tools/dev_test_preparation.gd — 1014行 — 34 func

## systems（详细层）

### scripts/systems/buff_system/buff_manager.gd — 105行 — 9 func
L26 func add_buff
L39 func remove_buff
L48 func get_effective_value
L63 func tick
L78 func get_buff_count
L83 func get_stat_buff_count
L92 func has_buff
L97 func get_remaining
L104 func clear_all

### scripts/systems/buff_system/test_all_player_tags.gd — 167行 — 4 func
L87 func _init
L100 func _test_tag
L116 func _apply_tag
L160 func _total

### scripts/systems/buff_system/test_buff_manager.gd — 195行 — 15 func
L16 func _init
L36 ---- = ----
L38 ---- = ----
L40 func test_single_mult_buff
L48 func test_single_flat_buff
L56 func test_mixed_buffs
L66 func test_multiple_mult
L75 func test_tick_expire
L96 func test_manual_remove
L114 func test_same_stat_multiple_flat
L123 func test_overwrite_same_id
L133 func test_different_stats
L146 func test_empty_no_buff
L153 func test_permanent_buff
L162 func test_tick_partial
L174 ---- = ----
L176 ---- = ----
L178 func _assert_eq
L188 func _total

### scripts/systems/buff_system/test_skill_mults.gd — 274行 — 31 func
L14 func _init
L36 ---- = ----
L38 ---- = ----
L40 func test_cost_single_discount
L47 func test_cost_increase
L54 func test_cost_stack
L62 func test_cost_expire
L70 func test_cd_single_discount
L77 func test_cd_expire
L85 func test_effect_single
L93 func test_effect_consume_reset
L102 func test_effect_diminishing
L111 func test_effect_mixed_mults
L128 func test_bonus_uses
L138 func test_default_no_cards
L146 func test_overwrite_same_id
L154 func test_manual_remove
L169 ---- = ----
L171 ---- = ----
L173 func _make_player
L186 func _get_player_code
L195 func add_skill_cost_mult
L198 func get_skill_cost_mult
L204 func add_skill_cd_mult
L207 func get_skill_cd_mult
L213 func add_next_skill_mult
L216 func get_and_consume_next_skill_mult
L229 func remove_skill_cost_mult
L232 func remove_skill_cd_mult
L235 func add_skill_bonus_uses
L240 func get_skill_bonus_uses
L243 func _process_discount_cards
L247 func _tick_mult_dict
L258 func _assert_eq
L267 func _total

### scripts/systems/buff_system/test_status_lights.gd — 221行 — 20 func
L15 func _init
L33 ---- = ----
L35 ---- = ----
L37 func test_turn_on
L45 func test_turn_off
L53 func test_auto_expire
L64 func test_tick_partial
L76 func test_cc_immune_blocks_cc
L93 func test_cc_immune_allows_non_cc
L105 func test_vulnerable_multiplier
L114 func test_overwrite_same_light
L125 func test_different_lights_independent
L136 func test_turn_off_by_type
L149 ---- = ----
L151 ---- = ----
L153 func _make_player
L164 func _get_player_status_code
L173 func is_status_active
L176 func turn_on_light
L185 func turn_off_light
L188 func turn_off_lights_by_type
L192 func _tick_status_lights
L205 func _assert_eq
L214 func _total

### scripts/systems/buff_system/test_stealth_checks.gd — 171行 — 12 func
L14 func _init
L28 ---- = ----
L30 ---- = ----
L33 func _sim_get_enemies
L48 func _sim_get_nearest_enemy
L59 func _make_player
L63 ---- = ----
L65 ---- = ----
L67 func test_stealth_excluded_from_enemies
L80 func test_all_stealth_returns_null
L96 func test_invincible_still_in_enemies
L108 func test_partial_stealth
L121 func test_unstealth_visible_again
L139 func test_stealth_target_drops_tracking
L151 ---- = ----
L153 ---- = ----
L155 func _assert_eq
L164 func _total

### scripts/systems/buff_system/test_tick_effects.gd — 277行 — 24 func
L14 func _init
L33 ---- = ----
L35 ---- = ----
L37 func test_regen
L47 func test_dot
L56 func test_expire
L72 func test_stack_regen_and_dot
L84 func test_stamina_cap
L95 func test_stamina_floor
L109 func test_overwrite_same_id
L121 func test_manual_remove
L135 func test_invincible_blocks_dot
L154 func test_dot_expire_under_invincible
L167 func test_total_tick_rate
L178 ---- = ----
L180 ---- = ----
L182 func _make_player
L196 func _get_player_code
L209 func is_status_active
L212 func turn_on_light
L221 func turn_off_light
L224 func add_tick_effect
L227 func remove_tick_effect
L230 func has_tick_effect
L233 func get_total_tick_rate
L240 func _process_tick_effects
L261 func _assert_eq
L270 func _total

### scripts/systems/event_bus/event_bus.gd — 128行 — 10 func
L65 func emit_event
L72 func subscribe
L78 func unsubscribe
L85 func wire_sources
L98 func _on_ball_caught
L101 func _on_player_defeated
L106 func dump_log
L110 func category_stats
L120 func clear_log
L125 func get_bus

### scripts/systems/inventory/inventory_manager.gd — 380行 — 29 func
L12 signal inventory_changed
L13 signal item_added
L14 signal item_removed
L17 func _ready
L22 func _load_item_definitions
L52 func _on_save_loaded
L57 func reload_item_defs
L63 func _ensure_inventory_structure
L75 func get_item_def
L81 func get_all_items
L85 func get_items_by_type
L93 func get_items_by_sub_type
L101 func get_items_by_rarity
L109 func get_backpack_items
L115 func get_item_count
L125 func has_item
L129 func get_max_slots
L135 func get_used_slots
L141 func is_full
L145 func add_item
L204 func remove_item
L233 func get_backpack_by_type
L243 func get_backpack_equipment
L247 func get_backpack_consumables
L251 func clear_all
L259 func get_rarity_color
L275 func get_rarity_name
L291 func get_all_rarities
L298 func _remove_one_equipment
L318 func equip_to_character
L347 func unequip_from_character
L363 func get_backpack_by_slot

### scripts/systems/nutrition/nutrition_manager.gd — 180行 — 12 func
L6 signal food_consumed
L7 signal food_cleared
L25 func _ready
L29 func _load_foods_data
L70 func reload_foods_data
L75 func get_all_foods
L80 func get_foods_by_rarity
L89 func get_food
L95 func consume_food
L130 func get_active_food_id
L135 func get_active_bonus
L150 func get_team_bonuses
L162 func clear_active_food
L169 func load_from_save

### scripts/systems/reward_system.gd — 226行 — 13 func
L5 ---- 奖励配置 ----
L33 signal rewards_granted
L36 func _ready
L43 func grant_rewards
L97 func get_win_streak
L102 func reset_win_streak
L107 func set_reward_enabled
L114 func update_config
L123 func _save_config
L133 func _load_config
L152 ---- 比赛历史记录 ----
L160 func record_match_history
L197 func get_match_history
L202 func clear_match_history
L208 func _save_history
L216 func _load_history

### scripts/systems/spirit_system/ai_msg_source.gd — 92行 — 8 func
L8 signal ai_msg
L21 func start_tracking
L41 func stop_tracking
L58 func get_msgs
L68 func _on_status
L75 func _on_mark
L79 func _on_toggle
L83 func _is_tracked
L87 func _push

### scripts/systems/spirit_system/handler/ball_route.gd — 295行 — 23 func
L7 func _apply_ball_dmg_up
L22 func _apply_ball_dmg_down
L38 func _apply_ball_penetrate
L45 func _apply_ball_armor
L53 func _apply_ball_speed_up
L69 func _apply_ball_speed_down
L86 func _apply_ball_range_up
L106 func _apply_ball_range_down
L116 func _apply_ball_lockon
L135 func _apply_ball_tracking
L154 func _apply_ball_boomerang
L162 func _apply_ball_straight
L175 func _apply_ball_bounce_enhance
L183 func _apply_ball_sure_hit
L190 func _apply_ball_transform
L197 func _apply_ball_stealth
L207 func _apply_ball_spread
L216 func _apply_ball_in_flight_boost
L226 func _apply_ball_recall
L235 func _apply_to_caster_ball
L260 func _apply_ball_manual_steering
L279 func _apply_ball_carry_push
L287 func _apply_field_vision_block

### scripts/systems/spirit_system/handler/base_route.gd — 988行 — 42 func
L6 signal effect_applied
L7 signal effect_finished
L24 ---- 优先级队列 ----
L55 func _default_ball_mods
L77 func _ensure_ball_mods
L84 func _mark_expiry
L95 func reset_ball_mods
L100 func reset_ball_mods_for
L104 func take_ball_mods_snapshot
L118 func _view_ball_mods
L132 func get_modified_ball_damage
L139 func get_modified_ball_speed
L144 func get_modified_ball_range
L149 func is_ball_penetrating
L153 func is_ball_boomerang
L158 func is_ball_tracking
L163 func get_tracking_target
L167 func get_tracking_turn_speed
L171 func has_ball_aoe
L176 func get_ball_aoe_radius
L180 func get_ball_aoe_damage_pct
L184 func trigger_boomerang
L195 func _register_timed_effect
L209 func remove_tag_effect
L220 func _get_caster
L232 func _get_enemies
L244 func _get_nearest_enemy
L261 func _get_trigger
L275 func _get_obstacle_manager
L286 func _get_field_zone_manager
L298 func _get_field_physics_manager
L309 func _get_illusion_manager
L320 func _get_element_color
L336 func _get_player_targets
L374 func apply_toggle_shield
L387 func remove_toggle_shield
L397 func _get_all_enemies
L408 func consume_hit_tags
L430 func clear_hit_tags
L435 func apply_tag_effect
L450 func _do_apply_tag
L472 ---- 对球效果（2026-09-19 Step2：全部带 caster_id，写入该施法者自己的准备区） ----
L576 ---- 场地标签 - 区域效果(07-10) ----
L599 ---- 召唤物标签 (30-31，工单23水木快牙系；分发口=布场代+集成复核) ----
L613 ---- 球员标签 - 属性(01-16) ----
L662 ---- 球员标签 - 状态(17-20) ----
L675 ---- 波3 球员管道变体（09 工单） ----
L704 ---- 波5（11 工单） ----
L714 ---- 工单12 OP_COMBO（合体半装，主人裁方案a） ----
L718 ---- 球员标签 - 体力(21-26) ----
L737 ---- 球员标签 - 运动(27-30) ----
L750 ---- 球员标签 - 能量(31-38) ----
L775 ---- 球员标签 - 元灵(39-45) ----
L797 ---- 球员标签 - 控制(46-49) ----
L810 ---- 球员标签 - 交互(50-51) ----
L834 func _init_priority_table
L836 ---- BALL类 ----
L870 ---- FIELD类 ----
L889 ---- PLAYER类 ----
L962 func get_tag_priority
L967 func queue_tag_effect
L975 func _flush_pending_tags

### scripts/systems/spirit_system/handler/field_route.gd — 510行 — 30 func
L15 func _ai_direct_place_field
L33 func _apply_field_obs_add
L71 func _apply_field_drain_wall
L99 func _apply_field_obs_clear
L118 func _apply_player_shield_obstacle
L139 func _apply_field_obs_move
L141 func _apply_field_obs_lock
L143 func _apply_field_terra_change
L145 func _apply_field_terra_revert
L147 func _apply_field_zone_mark
L149 func _apply_field_zone_clear
L155 func _apply_summon_spawn
L182 func _apply_summon_merge
L202 func _get_summon_manager
L206 func _apply_field_zone_effect
L268 func _build_zone_params
L312 func _register_pending_zone_spawn
L324 func _ensure_ball_landing_hooks
L341 func _on_ball_first_land
L345 func _on_ball_stopped
L349 func _consume_pending_zone_spawns
L364 func _cleanup_expired_zone_spawns
L373 func _cleanup_pending_in_flight
L383 func _ensure_in_flight_hooks
L394 func _on_attack_launched
L423 func _apply_field_illusion_add
L459 func _apply_summon_limit_up
L480 func _apply_enhance_next
L496 func _team_of_caster
L501 func _apply_field_illusion_clear

### scripts/systems/spirit_system/handler/player_route.gd — 503行 — 34 func
L5 func _apply_player_stat_buff
L22 func _apply_player_status
L37 func _apply_player_vulnerable
L47 func _apply_player_reveal
L63 func _apply_player_heal_block
L75 func _apply_player_reflect
L85 func _apply_player_element_shield
L95 func _apply_player_energy_share
L104 func _apply_player_charge_stock
L113 func _apply_player_on_hit_expire
L124 func _apply_player_skill_copy_last
L148 func _apply_player_skill_share_copy
L174 func _apply_player_mark_apply
L225 func transfer_marks_on_hit
L268 func _apply_player_combo_ready
L285 func _connect_combo_signals
L300 func _on_combo_formed
L323 func _on_combo_broken
L340 func _apply_player_hp_heal_pct
L350 func _apply_player_hp_damage_pct
L364 func _apply_player_hp_heal_flat
L373 func _apply_player_hp_damage_flat
L386 func _apply_player_hp_regen
L398 func _apply_player_hp_dot
L413 func _apply_player_unroot
L421 func _apply_player_energy_pct
L434 func _apply_player_energy_flat
L448 func _apply_player_spirit_cost
L456 func _apply_player_spirit_cd
L464 func _apply_player_spirit_uses
L475 func _apply_player_spirit_double
L481 func _apply_player_spirit_half
L489 func _apply_player_teleport
L497 func _apply_player_return

### scripts/systems/spirit_system/skill_outline_node.gd — 80行 — 5 func
L23 func setup_ring
L34 func setup_strip
L48 func _draw
L57 func _draw_ring
L66 func _draw_strip

### scripts/systems/spirit_system/skill_state_manager.gd — 762行 — 44 func
L6 signal skill_activated
L7 signal skill_cancelled
L8 signal skill_released
L67 func get_operator
L74 func get_operator_substate
L86 func get_active_operator
L92 func confirm_substate
L100 func confirm_substate_at
L143 func confirm_drag
L154 func clear_substate_selection
L167 func is_key_migration_active
L178 func get_drag_snap_radius
L192 func _notify_summon_order
L209 func _skill_reclick_mode
L223 func _skill_drag_enabled
L233 func is_drag_skill
L239 func get_space_mode
L253 func _clear_operator_context
L267 func register_ai_input_source
L272 func set_ai_aim
L278 func get_ai_aim
L284 func clear_ai_input_source
L300 func get_active_operation
L307 func ai_activate_skill
L331 func _tick_ai_activations
L352 signal combo_formed
L353 signal combo_broken
L367 func register_combo_ready
L379 func unregister_combo_ready
L384 func get_combo_readies
L389 func get_combo_states
L396 func try_form_combos
L418 func _pair_compatible
L439 func _form_combo
L451 func _process
L479 func _ready
L485 func setup_player_skills
L497 func on_skill_key_pressed
L562 func _trigger_midfly
L598 func cancel_active_skill
L611 func _activate_skill
L649 func _cancel_active_skill
L667 func _release_skill
L685 func on_skill_released_complete
L698 func on_cooldown_finished
L711 func get_active_skill
L719 func is_mouse_required
L733 func _get_skill_data
L757 func cleanup_player

### scripts/systems/spirit_system/skill_visual_manager.gd — 253行 — 18 func
L13 ---- 引用（由 battle_manager.setup() 注入） ----
L29 func _ready
L34 func _load_tags_registry
L49 func setup
L72 func _on_player_shield_spawned
L84 func on_skill_triggered
L116 func on_effect_finished
L125 func clear_all
L134 func _apply_ball_outline
L148 func _apply_player_outline
L162 func _apply_field_outline
L184 func _create_ring_panel
L191 func _create_facing_strip
L199 func _remove_outline
L211 func _on_ball_hit_player
L216 func _on_ball_caught
L225 func _load_skills_data
L238 func _get_skill_data
L244 func _get_element_color

### scripts/systems/spirit_system/spirit_skill_trigger.gd — 698行 — 40 func
L7 signal skill_triggered
L8 signal skill_effect_applied
L9 signal skill_ui_feedback
L33 func _ready
L46 func _load_tags_registry
L65 func setup_battle_refs
L76 func set_player_skills
L106 func _charges_cfg_of
L113 func _init_charge_pool
L122 func get_skill_charges
L129 func _subscribe_passives
L150 func _event_name_to_enum
L163 func _on_passive_event
L182 func _check_condition
L219 func trigger_skill
L266 func _fire_skill
L298 func _load_skills_data
L312 func _get_skill_data
L321 func _apply_passive_sync_lock
L339 func _execute_skill_tags
L365 func _build_tag_params
L393 func _toggle_shield_base_params
L397 func _toggle_skill
L456 func _on_shield_toggle_auto_closed
L463 func _consume_energy
L499 func _get_player_by_id
L506 func _set_skill_cooldown
L526 func _record_cast
L542 func get_last_enemy_cast
L550 signal player_skills_changed
L557 func _active_count
L566 func put_shared_copy
L578 func take_shared_copy
L588 func _process
L624 func get_skill_cooldown
L630 func get_skill_cooldown_ratio
L642 func add_player_skill
L656 func get_player_skills
L664 func remove_player_skill
L671 func has_tag
L675 func get_tag_data
L681 func _on_effect_applied
L685 func _on_effect_finished
L689 func _send_ui_feedback

### scripts/systems/spirit_system/spirit_system_manager.gd — 138行 — 13 func
L7 signal skill_used
L8 signal effect_applied
L9 signal effect_finished
L10 signal ui_feedback
L19 func _ready
L60 func initialize
L73 func set_player_skills
L82 func use_skill
L95 func get_skill_cooldown
L101 func get_player_skills
L107 func has_tag
L113 func get_tag_data
L119 func _on_skill_triggered
L123 func _on_skill_effect_applied
L127 func _on_ui_feedback
L132 func _on_effect_applied_handler
L136 func _on_effect_finished_handler

### scripts/systems/spirit_system/spirit_tag_effect_handler.gd — 56行 — 2 func
L8 func _ready
L14 func _process

### scripts/systems/spirit_system/spirit_ui.gd — 719行 — 26 func
L6 ---- 数据 ----
L16 ---- UI 引用 ----
L32 signal close_requested
L35 func _ready
L44 func _load_data
L80 func refresh_data
L90 ---- = ----
L92 ---- = ----
L94 func _build_ui
L151 ---- 左侧面板 ----
L153 func _build_left_panel
L184 func _create_spirit_icon
L222 func _on_icon_input
L227 ---- 右侧面板 ----
L229 func _build_right_panel
L237 ---- 头像（圆形） ----
L244 ---- 名称 ----
L252 ---- 等级 ----
L260 ---- 描述 ----
L269 ---- 上场技能标签 ----
L309 ---- 3个按钮 ----
L335 ---- 分隔线 ----
L342 ---- 技能库标题 ----
L350 ---- 技能库滚动区域 ----
L362 ---- = ----
L364 ---- = ----
L366 func _select_spirit
L383 func _update_equipped_slots
L416 func _fill_skill_slot
L432 func _on_slot_right_click
L437 func _update_skill_library
L452 func _create_library_entry
L524 func _on_entry_input
L529 ---- = ----
L531 ---- = ----
L533 func _show_skill_popup
L618 ---- = ----
L620 ---- = ----
L622 func _on_unlock_skill
L640 func _on_edit_skills
L644 func _on_confirm
L648 func _on_upgrade_spirit
L667 func _on_close
L671 ---- = ----
L673 ---- = ----
L675 func _get_skill_by_id
L683 func _get_skill_icon_color
L692 func _get_element_color
L704 func _clear_panel
L713 func _set_panel_color

### scripts/systems/spirit_system/team_combo_tracker.gd — 236行 — 12 func
L10 signal team_combo_formed
L28 func _ready
L34 func setup
L44 func _load_table
L81 func _process
L93 func _try_form_combos
L148 func _apply_settlement
L167 func _resolve_scope
L185 func _resolve_battle_manager
L194 func _members_desc
L206 func register_cast
L224 func _on_skill_used
L230 func get_formed_count

### scripts/systems/summon/summon_entity.gd — 190行 — 16 func
L20 func setup
L33 func _build_hitbox
L47 func _physics_process
L67 func _frame_count
L74 func enter_burrow
L83 func exit_burrow
L91 func consume
L95 func _consume
L108 func _ready
L114 func _build_2d_visual
L124 func _draw_visual
L141 func _emit_state_changed
L149 func _on_spawned
L155 func on_ball_proximity
L184 func _find_owner_node
L188 func _bus

### scripts/systems/summon/summon_manager.gd — 191行 — 16 func
L18 func _ready
L23 func _load_types
L32 func _bus
L40 func spawn
L71 func despawn
L82 func get_summons_of
L91 func set_active_limit
L97 func register_auto_spawner
L102 func stop_auto_spawner
L107 func set_active_limit_timed
L113 func register_empower
L117 func _physics_process
L147 func try_merge
L171 func _count_live
L180 func _team_of
L185 func _find_node_by_instance_id

### scripts/systems/talent/talent_system.gd — 232行 — 14 func
L18 func _ready
L22 func _load_tree
L39 func try_unlock
L59 func get_node_data
L65 func get_used_points
L74 func setup_battle
L95 func get_team_bonuses
L109 func _on_talent_event
L148 func _process
L156 func apply_manual_skills
L174 func _event_name_to_enum
L186 func _check_condition
L212 func _find_tag_handler
L222 func _get_all_players

### scripts/systems/training/training_manager.gd — 217行 — 16 func
L15 signal training_changed
L16 signal field_level_changed
L19 func _ready
L23 func _load_growth_curves
L47 func _generate_default_growth_curves
L97 func _save_growth_curves
L110 func get_field_level
L114 func get_train_cost
L118 func get_field_upgrade_cost
L127 func get_stat_max
L143 func can_train
L152 func get_current_bonus
L157 func train_stat
L176 func upgrade_field
L193 func get_all_growth_curves
L197 func set_growth_curves
L202 func get_curve_for_char
L206 func update_curve_for_char


## test（摘要层）

- scripts/test/aabb_probe.gd — 93行 — 6 func
- scripts/test/ball_proxy_3d.gd — 212行 — 8 func
- scripts/test/battle_field_3d_test.gd — 500行 — 20 func
- scripts/test/camera_check.gd — 111行 — 2 func
- scripts/test/dev_panels_test_headless.gd — 100行 — 5 func
- scripts/test/field_tag_test.gd — 953行 — 35 func
- scripts/test/field_tag_test_panel.gd — 2325行 — 68 func
- scripts/test/field_zone_3d.gd — 274行 — 23 func
- scripts/test/inventory_test_headless.gd — 234行 — 13 func
- scripts/test/minimal_render.gd — 104行 — 2 func
- scripts/test/player_3d_test.gd — 2408行 — 80 func
- scripts/test/player_save_test.gd — 185行 — 10 func
- scripts/test/player_save_test_headless.gd — 169行 — 11 func
- scripts/test/player_tag_test.gd — 1782行 — 56 func
- scripts/test/render_capture.gd — 83行 — 4 func
- scripts/test/render_capture2.gd — 116行 — 5 func
- scripts/test/serialize_utils.gd — 30行 — 2 func
- scripts/test/simple_check.gd — 11行 — 1 func
- scripts/test/test_3d_arena_selfcheck.gd — 237行 — 6 func
- scripts/test/test_gui_screenshot.gd — 115行 — 3 func
- scripts/test/test_player_3d.gd — 181行 — 11 func
- scripts/test/verify_player3d.gd — 43行 — 1 func

## test3d（摘要层）

- scripts/test3d/dev_flow_probe.gd — 64行 — 1 func
- scripts/test3d/diag_run_anim.gd — 44行 — 2 func
- scripts/test3d/diag_talent.gd — 13行 — 1 func
- scripts/test3d/facing_calib_probe.gd — 24行 — 1 func
- scripts/test3d/full_ai_platform/full_ai_platform.gd — 172行 — 5 func
- scripts/test3d/full_ai_platform/loadout_loader.gd — 213行 — 8 func
- scripts/test3d/full_ai_platform/observe_layer.gd — 324行 — 19 func
- scripts/test3d/full_ai_platform/platform_probe.gd — 637行 — 21 func
- scripts/test3d/full_ai_platform/play_trace_recorder.gd — 105行 — 6 func
- scripts/test3d/full_ai_platform/roster_panel.gd — 215行 — 7 func
- scripts/test3d/live_talent_editor.gd — 10行 — 1 func
- scripts/test3d/regression/shot_basic_ui.gd — 34行 — 2 func
- scripts/test3d/regression/shot_operator.gd — 136行 — 3 func
- scripts/test3d/regression/tag_audit.gd — 97行 — 3 func
- scripts/test3d/regression/test_3d_effect_compat.gd — 117行 — 4 func
- scripts/test3d/regression/test_3d_rules_parity.gd — 65行 — 1 func
- scripts/test3d/regression/test_activation_chain.gd — 229行 — 9 func
- scripts/test3d/regression/test_ai_jump.gd — 159行 — 3 func
- scripts/test3d/regression/test_ai_msg_source.gd — 94行 — 3 func
- scripts/test3d/regression/test_air_throw.gd — 115行 — 3 func
- scripts/test3d/regression/test_aoe_targets.gd — 76行 — 5 func
- scripts/test3d/regression/test_ball_mods_isolation.gd — 75行 — 3 func
- scripts/test3d/regression/test_ballistic_ball.gd — 201行 — 2 func
- scripts/test3d/regression/test_basic_ui.gd — 280行 — 4 func
- scripts/test3d/regression/test_charge_pool.gd — 80行 — 3 func
- scripts/test3d/regression/test_class3_usage_diagnosis.gd — 185行 — 5 func
- scripts/test3d/regression/test_comm_protocol_v2.gd — 144行 — 4 func
- scripts/test3d/regression/test_counter.gd — 65行 — 3 func
- scripts/test3d/regression/test_dev_skill_save.gd — 108行 — 3 func
- scripts/test3d/regression/test_element_editor.gd — 37行 — 1 func
- scripts/test3d/regression/test_enemy_status_marker.gd — 129行 — 3 func
- scripts/test3d/regression/test_energy_path.gd — 241行 — 5 func
- scripts/test3d/regression/test_event_bus.gd — 65行 — 5 func
- scripts/test3d/regression/test_event_registry_v2.gd — 81行 — 3 func
- scripts/test3d/regression/test_events_a_bc.gd — 89行 — 2 func
- scripts/test3d/regression/test_field_knowledge.gd — 94行 — 4 func
- scripts/test3d/regression/test_fp_mode.gd — 158行 — 3 func
- scripts/test3d/regression/test_full_ai_platform.gd — 169行 — 3 func
- scripts/test3d/regression/test_item_granter.gd — 121行 — 4 func
- scripts/test3d/regression/test_loadout_23_fenny.gd — 140行 — 4 func
- scripts/test3d/regression/test_on_hit_chain.gd — 152行 — 3 func
- scripts/test3d/regression/test_operator_e2e.gd — 280行 — 10 func
- scripts/test3d/regression/test_operator_routing.gd — 174行 — 5 func
- scripts/test3d/regression/test_operator_selector.gd — 173行 — 3 func
- scripts/test3d/regression/test_original_trio.gd — 382行 — 14 func
- scripts/test3d/regression/test_outer_skill_ai_diagnosis.gd — 328行 — 11 func
- scripts/test3d/regression/test_passive.gd — 67行 — 2 func
- scripts/test3d/regression/test_pipeline.gd — 48行 — 2 func
- scripts/test3d/regression/test_player_jump.gd — 114行 — 2 func
- scripts/test3d/regression/test_prethrow_hook.gd — 137行 — 7 func
- scripts/test3d/regression/test_review_batch1.gd — 115行 — 5 func
- scripts/test3d/regression/test_review_batch2.gd — 200行 — 5 func
- scripts/test3d/regression/test_root_target.gd — 70行 — 3 func
- scripts/test3d/regression/test_shield_obstacle.gd — 150行 — 5 func
- scripts/test3d/regression/test_shuimu_skills.gd — 155行 — 4 func
- scripts/test3d/regression/test_skill_bar_dynamic.gd — 114行 — 3 func
- scripts/test3d/regression/test_skill_copy.gd — 113行 — 5 func
- scripts/test3d/regression/test_spirit_ai_foundation.gd — 205行 — 6 func
- scripts/test3d/regression/test_spirit_ai_integration.gd — 357行 — 8 func
- scripts/test3d/regression/test_spirit_ai_switches.gd — 150行 — 5 func
- scripts/test3d/regression/test_spirit_ai_wave_a.gd — 258行 — 5 func
- scripts/test3d/regression/test_spirit_ai_wave_b.gd — 257行 — 3 func
- scripts/test3d/regression/test_spirit_ai_wave_c.gd — 469行 — 8 func
- scripts/test3d/regression/test_spirit_ai_wave_d.gd — 359行 — 4 func
- scripts/test3d/regression/test_spirit_ai_wave_e.gd — 239行 — 3 func
- scripts/test3d/regression/test_stub_summon_entity.gd — 8行 — 0 func
- scripts/test3d/regression/test_substitute_flow.gd — 150行 — 2 func
- scripts/test3d/regression/test_summon_skills.gd — 153行 — 4 func
- scripts/test3d/regression/test_summon_system.gd — 162行 — 5 func
- scripts/test3d/regression/test_summon_visual_bridge.gd — 130行 — 4 func
- scripts/test3d/regression/test_summon_visual_platform.gd — 123行 — 4 func
- scripts/test3d/regression/test_summon_visuals.gd — 170行 — 3 func
- scripts/test3d/regression/test_talent.gd — 87行 — 2 func
- scripts/test3d/regression/test_talent_editor.gd — 172行 — 5 func
- scripts/test3d/regression/test_target_audit.gd — 145行 — 4 func
- scripts/test3d/regression/test_team_combo.gd — 177行 — 7 func
- scripts/test3d/regression/test_three_routes_e2e.gd — 106行 — 3 func
- scripts/test3d/regression/test_transfer_order_27.gd — 125行 — 4 func
- scripts/test3d/regression/test_walk_consumption_diagnosis.gd — 221行 — 4 func
- scripts/test3d/regression/test_wave3_primitives.gd — 160行 — 4 func
- scripts/test3d/regression/test_wave4_ball_params.gd — 146行 — 5 func
- scripts/test3d/regression/test_wave5_extensions.gd — 201行 — 7 func
- scripts/test3d/regression/test_wave6_finale.gd — 198行 — 6 func
- scripts/test3d/regression/test_wave7_finale.gd — 120行 — 5 func
- scripts/test3d/regression/test_wave_op1_patch.gd — 284行 — 9 func
- scripts/test3d/regression/test_zone_path_preview.gd — 115行 — 4 func
- scripts/test3d/regression/test_zone_spawn_at.gd — 85行 — 3 func
- scripts/test3d/unity_scene_parity_test.gd — 434行 — 26 func

## ui（详细层）

### scripts/ui/base_system.gd — 712行 — 19 func
L10 func _ready
L17 func _build_base_ui
L71 func _build_currency_bar
L108 func _update_currency_display
L118 func _build_navigation
L156 func _switch_tab
L173 func _show_tab
L189 func _show_equipment_tab
L290 func _create_item_card
L427 func _get_fallback_icon_path
L468 func _show_training_tab
L527 func _create_training_card
L559 func _show_nutrition_tab
L649 func _show_shop_tab
L680 func _on_close
L685 func _on_open_inventory
L689 func _on_upgrade_field
L702 func _on_go_to_preparation
L708 func _on_view_food
L712 signal closed

### scripts/ui/character_selection.gd — 103行 — 7 func
L4 signal character_selected
L11 func _ready
L15 func _setup_ui
L46 func load_characters
L58 func _create_character_card
L89 func _on_character_selected
L96 func _on_close
L101 func get_selected_character

### scripts/ui/character_system.gd — 432行 — 7 func
L5 signal closed
L41 ---- 右侧详情面板排版规范常量 === === 添加新属性时只需修改内容，不需要修改位置计算 ----
L84 func _ready
L93 func _load_data
L105 func _build_ui
L135 ---- 左侧底板（带圆角边框的独立面板） ----
L174 ---- 右侧详情面板 === === 排版规范（添加新属性时只需修改类成员 stat_keys 数组） ----
L176 ---- 右侧底板（带圆角边框，比内容区大8px） ----
L188 ---- 创建滚动容器（透明背景，让底板透出来） ----
L216 ---- 在content内添加所有元素 ----
L316 func _build_avatar_button
L329 func _build_large_avatar_placeholder
L362 func _select_character
L430 func _on_close

### scripts/ui/main_menu.gd — 432行 — 19 func
L13 func _ready
L48 func _show_mode_selection
L104 func _clear_mode_selection
L112 func _on_enter_player_mode
L124 func _on_enter_admin_mode
L136 func _on_back_to_mode_selection
L150 func _build_main_menu
L286 func _hide_menu_interactive_nodes
L293 func _show_menu_interactive_nodes
L299 func _on_start_match
L307 func _on_open_characters
L336 func _on_open_spirits
L367 func _on_open_base
L389 func _on_open_element_editor
L398 func _on_open_talent_editor
L407 func _on_open_dev_settings
L416 func _on_toggle_reward
L423 func _rebuild_reward_button
L431 func _on_open_trade

### scripts/ui/match_result_ui.gd — 499行 — 17 func
L29 signal result_confirmed
L32 func _ready
L78 func setup
L88 ---- UI构建 ----
L90 func _add_result_header
L109 func _add_score_display
L145 func _add_tab_bar
L164 ---- Tab内容 ----
L166 func _show_tab
L190 func _show_battle_report
L211 func _show_data_panel
L229 func _show_rewards_panel
L343 func _show_confirm_panel
L374 ---- 辅助UI方法 ----
L376 func _add_section_title
L384 func _add_team_stats
L404 func _add_player_data_card
L441 func _add_stat_row
L460 func _add_reward_row
L480 func _create_card
L497 func _on_confirm_pressed

### scripts/ui/preparation_ui.gd — 1929行 — 58 func
L16 signal strategy_changed
L17 signal player_substituted
L18 signal spirit_changed
L19 signal match_started_from_prep
L20 signal back_to_menu_requested
L76 func _ready
L84 func _process
L93 func _build_ui
L123 ---- 第一行：球员状态（3个独立卡片，横向排列） ----
L126 ---- 第二行：元灵选择（3个独立卡片，横向排列） ----
L129 ---- 第三行：装备穿戴（3个独立卡片，横向排列） ----
L132 ---- 第四行：训练系统 ----
L135 ---- 第五行：战术策略 ----
L138 ---- 底部：开始比赛按钮 ----
L147 ---- 底部：中场休息倒计时（默认隐藏） ----
L159 ---- 第一行：球员状态 ----
L161 func _build_player_row
L178 func _build_player_card
L314 ---- 第二行：元灵选择 ----
L316 func _build_spirit_row
L332 func _build_spirit_card
L444 ---- 第三行：装备穿戴 ----
L464 func _build_equipment_row
L480 func _build_equipment_card
L542 ---- 第四行：训练系统 ----
L547 func _build_training_row
L562 func _build_training_card
L615 func _update_training_widget
L641 ---- 训练弹窗 ----
L648 func _on_open_training
L652 func _open_training_popup
L788 func _on_train_stat
L805 func _on_upgrade_field
L815 func _on_train_popup_bg_input
L820 func _close_training_popup
L827 func _update_equipment_widget
L865 ---- 装备选择弹窗 ----
L872 func _on_change_equipment
L878 func _open_equipment_select_popup
L1073 func _stat_key_to_name
L1084 func _on_equip_selected
L1102 func _on_unequip_equipment
L1120 func _on_equip_popup_bg_input
L1126 func _close_equipment_popup
L1134 ---- 第四行：战术策略 ----
L1136 func _build_strategy_panel
L1178 ---- 食物选择（全队，整场1种1次） ----
L1212 func _create_strategy_btn
L1224 ---- 数据加载 ----
L1226 func load_battle_data
L1239 func _update_player_widget
L1270 func _calc_player_bonuses
L1294 ---- 信号处理 ----
L1296 func _on_strategy_selected
L1319 func _player_strategy_to_name
L1327 func _rebuild_team_a_profiles
L1340 func _update_strategy_button_styles
L1349 ---- 职位分配（2026-06-17：玩家可自由给3个AI队友分配职位，不绑死） ----
L1350 func _on_role_clicked
L1372 func _find_role_occupier
L1382 func _refresh_role_btn
L1396 func _on_substitute_player
L1462 func _apply_substitute
L1486 func _close_player_popup
L1492 func _on_player_popup_bg_input
L1497 func _on_change_spirit
L1507 func _open_spirit_select_popup
L1648 func _on_spirit_selected
L1667 func _on_unequip_spirit
L1680 func _reset_spirit_widget
L1715 func _update_spirit_widget
L1805 func _on_spirit_popup_bg_input
L1811 func _close_spirit_popup
L1820 func set_half_time_mode
L1838 func _on_start_match
L1845 func _on_back_to_menu
L1852 ---- 食物系统 ----
L1855 func _refresh_food_list
L1886 func _on_eat_food
L1920 ---- 公开方法 ----
L1922 func set_ai_manager
L1925 func get_player_strategy
L1928 func get_team_strategy


