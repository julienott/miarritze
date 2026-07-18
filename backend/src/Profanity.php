<?php
declare(strict_types=1);

/**
 * Filtre anti-gros-mots (FR/EN) appliqué aux pseudos au join.
 * Volontairement simple : normalisation (minuscules, accents, leet) puis
 * recherche de sous-chaînes. Public jeune → mieux vaut trop strict que pas assez.
 */
final class Profanity
{
    private const WORDS = [
        // FR
        'merde', 'putain', 'pute', 'salope', 'salaud', 'connard', 'connasse',
        'encule', 'enculer', 'batard', 'chiotte', 'couille', 'nique', 'niquer',
        'bite', 'zizi', 'crotte', 'pd', 'fdp', 'ntm', 'tg',
        // EN
        'fuck', 'shit', 'bitch', 'asshole', 'bastard', 'dick', 'cunt',
        'whore', 'slut', 'nigger', 'nigga', 'porn', 'sex', 'hitler', 'nazi',
    ];

    public static function isClean(string $pseudo): bool
    {
        $normalized = self::normalize($pseudo);
        foreach (self::WORDS as $word) {
            if (str_contains($normalized, $word)) {
                return false;
            }
        }
        return true;
    }

    private static function normalize(string $text): string
    {
        $text = mb_strtolower($text, 'UTF-8');
        $converted = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $text);
        if ($converted !== false) {
            $text = $converted;
        }
        // Substitutions leet courantes
        $text = strtr($text, ['0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '@' => 'a', '$' => 's']);
        // Retire tout ce qui n'est pas une lettre (casse les séparateurs w_o_r_d)
        return preg_replace('/[^a-z]/', '', $text) ?? $text;
    }
}
