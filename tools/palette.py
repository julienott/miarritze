# Palette Miarritze — limitée et chaude, esprit Fez ensoleillé.
# Toutes les couleurs du jeu viennent d'ici (cohérence pixel art).

PALETTE = {
    # Structure
    "outline":      (58, 38, 52),      # contour universel, brun-prune sombre
    "black":        (24, 16, 28),
    "white":        (247, 241, 227),
    "cream":        (236, 225, 204),
    "cream_shade":  (214, 198, 170),
    # Ciel / mer
    "sky_high":     (64, 150, 210),
    "sky_low":      (150, 214, 236),
    "sky_dawn":     (255, 200, 140),
    "sea_deep":     (23, 78, 118),
    "sea_mid":      (32, 120, 154),
    "sea_turquoise":(64, 180, 188),
    "sea_foam":     (222, 244, 240),
    # Sable / terre
    "sand":         (238, 202, 128),
    "sand_shade":   (214, 168, 96),
    "sand_dark":    (178, 130, 74),
    "earth":        (140, 96, 60),
    # Basque !
    "red":          (206, 52, 52),
    "red_dark":     (150, 34, 40),
    "green":        (52, 128, 72),
    "green_dark":   (34, 88, 52),
    # Végétation
    "leaf":         (96, 168, 88),
    "leaf_dark":    (56, 118, 66),
    # Pierre / rocher
    "rock":         (120, 112, 116),
    "rock_light":   (164, 156, 152),
    "rock_dark":    (82, 74, 84),
    # Bâti
    "brick":        (188, 98, 70),
    "brick_dark":   (146, 70, 54),
    "roof":         (196, 84, 66),
    "wood":         (150, 104, 62),
    "wood_dark":    (108, 72, 46),
    # Personnage
    "skin":         (242, 201, 160),
    "skin_shade":   (214, 160, 110),
    "hair":         (90, 58, 40),
    "rope":         (196, 148, 84),
    # Accents
    "gold":         (244, 198, 62),
    "gold_dark":    (198, 146, 34),
    "orange":       (238, 140, 58),
    "sky_night":    (44, 60, 110),
    "purple":       (120, 80, 140),
    "grey_blue":    (108, 132, 156),
}


def px(name: str) -> tuple:
    return PALETTE[name] + (255,)
