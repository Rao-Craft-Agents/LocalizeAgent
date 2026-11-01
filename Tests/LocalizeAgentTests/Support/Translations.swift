import Foundation

/// The recipe app's strings in four languages: what the scripted model answers, read off each ask's own ids.
enum Translations {
    static let english: [String: String] = ["RECIPES_EMPTY_TITLE": "No recipes yet"]

    static let table: [String: [String: String]] = [
        "fr": [
            "Saved %lld recipes": "%lld recettes enregistrées",
            "Cooked by %1$@ in %2$lld minutes": "Cuisiné par %1$@ en %2$lld minutes",
            "Recipes": "Recettes", "Favorites": "Favoris", "Vegetarian only": "Végétarien uniquement", "Recipe name": "Nom de la recette",
            "Filters": "Filtres", "%lld recipes": "%lld recettes", "Search recipes": "Rechercher des recettes", "Clear All": "Tout effacer",
            "Removes every recipe from the list": "Retire toutes les recettes de la liste", "Remove every recipe?": "Retirer toutes les recettes ?",
            "Remove": "Retirer", "Cancel": "Annuler", "This cannot be undone.": "Cette action est irréversible.", "Quick": "Rapide",
            "Slow cook": "Mijotage", "No recipes yet": "Aucune recette pour l'instant",
            "Add a recipe to see it here.\nIt stays on this device.": "Ajoutez une recette pour la voir ici.\nElle reste sur cet appareil.",
            "Starter": "Entrée", "Main course": "Plat principal", "Dessert": "Dessert", "Course": "Plat", "New": "Nouveau",
            "Share Recipe": "Partager la recette",
        ],
        "de": [
            "Saved %lld recipes": "%lld Rezepte gesichert",
            "Cooked by %1$@ in %2$lld minutes": "In %2$lld Minuten von %1$@ gekocht",
            "Recipes": "Rezepte", "Favorites": "Favoriten", "Vegetarian only": "Nur vegetarisch", "Recipe name": "Rezeptname",
            "Filters": "Filter", "%lld recipes": "%lld Rezepte", "Search recipes": "Rezepte durchsuchen", "Clear All": "Alle löschen",
            "Removes every recipe from the list": "Entfernt alle Rezepte aus der Liste", "Remove every recipe?": "Alle Rezepte entfernen?",
            "Remove": "Entfernen", "Cancel": "Abbrechen", "This cannot be undone.": "Das kann nicht rückgängig gemacht werden.",
            "Quick": "Schnell", "Slow cook": "Schmoren", "No recipes yet": "Noch keine Rezepte",
            "Add a recipe to see it here.\nIt stays on this device.": "Füge ein Rezept hinzu, um es hier zu sehen.\nEs bleibt auf diesem Gerät.",
            "Starter": "Vorspeise", "Main course": "Hauptgang", "Dessert": "Nachtisch", "Course": "Gang", "New": "Neu",
            "Share Recipe": "Rezept teilen",
        ],
        "ja": [
            "Saved %lld recipes": "%lld件のレシピを保存しました",
            "Cooked by %1$@ in %2$lld minutes": "%1$@が%2$lld分で調理",
            "Recipes": "レシピ", "Favorites": "お気に入り", "Vegetarian only": "ベジタリアンのみ", "Recipe name": "レシピ名",
            "Filters": "フィルタ", "%lld recipes": "%lld件のレシピ", "Search recipes": "レシピを検索", "Clear All": "すべて消去",
            "Removes every recipe from the list": "リストからすべてのレシピを削除します", "Remove every recipe?": "すべてのレシピを削除しますか？",
            "Remove": "削除", "Cancel": "キャンセル", "This cannot be undone.": "この操作は取り消せません。", "Quick": "時短",
            "Slow cook": "じっくり煮込み", "No recipes yet": "レシピはまだありません",
            "Add a recipe to see it here.\nIt stays on this device.": "レシピを追加するとここに表示されます。\nこのデバイスに保存されます。",
            "Starter": "前菜", "Main course": "メインディッシュ", "Dessert": "デザート", "Course": "コース", "New": "新着",
            "Share Recipe": "レシピを共有",
        ],
        "ar": [
            "Saved %lld recipes": "تم حفظ %lld من الوصفات",
            "Cooked by %1$@ in %2$lld minutes": "طهاها %1$@ في %2$lld دقيقة",
            "Recipes": "الوصفات", "Favorites": "المفضلة", "Vegetarian only": "نباتي فقط", "Recipe name": "اسم الوصفة",
            "Filters": "عوامل التصفية", "%lld recipes": "%lld من الوصفات", "Search recipes": "البحث في الوصفات", "Clear All": "مسح الكل",
            "Removes every recipe from the list": "يزيل كل الوصفات من القائمة", "Remove every recipe?": "هل تريد إزالة كل الوصفات؟",
            "Remove": "إزالة", "Cancel": "إلغاء", "This cannot be undone.": "لا يمكن التراجع عن ذلك.", "Quick": "سريع",
            "Slow cook": "طهي بطيء", "No recipes yet": "لا توجد وصفات بعد",
            "Add a recipe to see it here.\nIt stays on this device.": "أضف وصفة لتراها هنا.\nتبقى على هذا الجهاز.",
            "Starter": "مقبلات", "Main course": "الطبق الرئيسي", "Dessert": "حلوى", "Course": "الطبق", "New": "جديد",
            "Share Recipe": "مشاركة الوصفة",
        ],
    ]

    /// The texts an ask names by id: the JSON object on the line after "Texts, by id:" or "Keys, by id:".
    static func asked(_ user: String) -> [String: String] {
        let lines = user.components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: { $0.hasSuffix(", by id:") }), header + 1 < lines.count,
              let object = try? JSONSerialization.jsonObject(with: Data(lines[header + 1].utf8)) as? [String: String] else { return [:] }
        return object
    }

    /// The language code an ask translates into: `French (fr, français)` is `fr`.
    static func language(_ user: String) -> String? {
        guard let range = user.range(of: #"\(([a-z]{2,3}(-[A-Za-z0-9]+)?)[,)]"#, options: .regularExpression) else { return nil }
        return String(user[range].dropFirst().dropLast())
    }

    /// `{"translations": {id: text}}` for every id the ask names that the table knows.
    static func answer(_ ask: FakeHostModel.Ask) -> Data {
        let texts = asked(ask.user)
        var answers: [String: String] = [:]
        if ask.system.contains("keys its code names in capitals") {
            for (id, key) in texts { if let text = english[key] { answers[id] = text } }
        } else if let code = language(ask.user), let table = table[code] {
            for (id, text) in texts { if let translated = table[text] { answers[id] = translated } }
        }
        return reply(answers)
    }

    static func reply(_ answers: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["translations": answers], options: [.sortedKeys])) ?? Data()
    }
}
