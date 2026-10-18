extends RefCounted

# Gerado por tools/gerar_carros.py (não editar à mão).
# wheels: pneus (a banda gira por cima no CarVisual); rear: rodas de trás
# (fumaça e marcas de pneu); blink: y da frente, y de trás e meia largura.

const MODELS := {
	"gt": {
		"wheels": [Rect2(-19.5, -24, 4.5, 11), Rect2(15, -24, 4.5, 11), Rect2(-20, 12, 5, 13), Rect2(15, 12, 5, 13)],
		"rear": [Vector2(-17.5, 24), Vector2(17.5, 24)],
		"blink": Vector3(-31, 31, 17),
	},
	"sedan": {
		"wheels": [Rect2(-19.5, -22, 4.5, 11), Rect2(15, -22, 4.5, 11), Rect2(-19.5, 9, 4.5, 12), Rect2(15, 9, 4.5, 12)],
		"rear": [Vector2(-17.25, 20), Vector2(17.25, 20)],
		"blink": Vector3(-30, 30, 17),
	},
	"taxi": {
		"wheels": [Rect2(-19.5, -22, 4.5, 11), Rect2(15, -22, 4.5, 11), Rect2(-19.5, 9, 4.5, 12), Rect2(15, 9, 4.5, 12)],
		"rear": [Vector2(-17.25, 20), Vector2(17.25, 20)],
		"blink": Vector3(-30, 30, 17),
	},
	"sport": {
		"wheels": [Rect2(-19.5, -23, 4.5, 11), Rect2(15, -23, 4.5, 11), Rect2(-20.5, 8, 5.5, 13.5), Rect2(15, 8, 5.5, 13.5)],
		"rear": [Vector2(-17.75, 20.5), Vector2(17.75, 20.5)],
		"blink": Vector3(-30, 30, 17),
	},
	"armored": {
		"wheels": [Rect2(-21, -23, 5, 14), Rect2(16, -23, 5, 14), Rect2(-21, 10, 5, 14), Rect2(16, 10, 5, 14)],
		"rear": [Vector2(-18.5, 23), Vector2(18.5, 23)],
		"blink": Vector3(-28, 30, 18),
	},
	"pickup": {
		"wheels": [Rect2(-21, -26, 5, 14), Rect2(16, -26, 5, 14), Rect2(-21, 14, 5, 14), Rect2(16, 14, 5, 14)],
		"rear": [Vector2(-18.5, 27), Vector2(18.5, 27)],
		"blink": Vector3(-32, 33, 18),
	},
	"muscle": {
		"wheels": [Rect2(-19.5, -23, 4.5, 12), Rect2(15, -23, 4.5, 12), Rect2(-20.5, 9, 5.5, 14.5), Rect2(15, 9, 5.5, 14.5)],
		"rear": [Vector2(-17.75, 22.5), Vector2(17.75, 22.5)],
		"blink": Vector3(-31, 31, 17),
	},
	"coupe": {
		"wheels": [Rect2(-19.5, -23, 4.5, 11.5), Rect2(15, -23, 4.5, 11.5), Rect2(-20, 9, 5, 14), Rect2(15, 9, 5, 14)],
		"rear": [Vector2(-17.5, 22), Vector2(17.5, 22)],
		"blink": Vector3(-30, 30, 17),
	},
	"f1": {
		"wheels": [Rect2(-21.5, -28.5, 8, 14), Rect2(13.5, -28.5, 8, 14), Rect2(-22.5, 12, 9, 17), Rect2(13.5, 12, 9, 17)],
		"rear": [Vector2(-18, 28), Vector2(18, 28)],
		"blink": Vector3(-30, 30, 14),
	},
	"legend": {
		"wheels": [Rect2(-21, -16, 5, 13), Rect2(16, -16, 5, 13), Rect2(-21, 12, 5, 14), Rect2(16, 12, 5, 14)],
		"rear": [Vector2(-18.5, 25), Vector2(18.5, 25)],
		"blink": Vector3(-26, 30, 17),
	},
	"van": {
		"wheels": [Rect2(-21, -26, 5, 13), Rect2(16, -26, 5, 13), Rect2(-21, 16, 5, 13), Rect2(16, 16, 5, 13)],
		"rear": [Vector2(-18.5, 28), Vector2(18.5, 28)],
		"blink": Vector3(-33, 33, 18),
	},
	"truck": {
		"wheels": [Rect2(-22, -56, 4, 12), Rect2(18, -56, 4, 12), Rect2(-23, 30, 4, 12), Rect2(19, 30, 4, 12), Rect2(-23, 45, 4, 12), Rect2(19, 45, 4, 12)],
		"rear": [Vector2(-21, 41), Vector2(21, 41), Vector2(-21, 56), Vector2(21, 56)],
		"blink": Vector3(-60, 60, 21),
	},
	"bus": {
		"wheels": [Rect2(-23, -50, 4, 14), Rect2(19, -50, 4, 14), Rect2(-23, 38, 4, 14), Rect2(19, 38, 4, 14)],
		"rear": [Vector2(-21, 51), Vector2(21, 51)],
		"blink": Vector3(-66, 66, 21),
	},
}
