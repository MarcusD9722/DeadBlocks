extends Node3D
## The server's record of one connected player. Its position comes from the player's movement
## messages; zombies (M1.4) target it through the Sim like any other player record.

var player_name := ""
var peer_id := 0
var net_id := 0
var yaw := 0.0
var pitch := 0.0
var flags := 0
var dead := false
## Set when the player's game has loaded the world around it; only ready players count as online.
var is_ready := false
var admin := false
## Movement checking: the last accepted position and when it arrived, and the current move id
## (bumped on every server correction so in-flight moves from before it are ignored).
var last_good := Vector3.ZERO
var last_move_ms := 0
var move_id := 0
## Connection health, for the log: when anything last arrived, and ENet's ping and packet loss.
var last_recv_ms := 0
var ping_ms := 0
var loss_pct := 0.0
## Set when the server itself ends the session (kick, signed in elsewhere).
var leave_reason := ""


func take_damage(_amount: float, _from: Vector3) -> void:
	# Players' health lives on their own PC until M1.4 sends damage to them.
	pass
