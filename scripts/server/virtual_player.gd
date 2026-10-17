extends Node3D
## A stand-in player for tests and benchmarks: zombies can target it like a real player.
## It does not move by itself, and damage is only counted.

var dead := false
var hits := 0
var damage_taken := 0.0


func take_damage(amount: float, _from: Vector3) -> void:
	hits += 1
	damage_taken += amount
