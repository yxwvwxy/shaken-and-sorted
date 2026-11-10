import Foundation

/// Chinese names for bar words, as Chinese cocktail menus write them. A name is
/// translated term by term, longest match first; words not in the glossary (usually
/// small brands) stay in English, the way they would on a Chinese menu.
enum CocktailGlossary {
    /// "Carpano Antica Vermouth" → "卡帕诺安提卡味美思", "Knob Creek Rye" → "Knob Creek 黑麦威士忌".
    /// Nil when no word is known, so a general translation can be tried instead.
    static func chinese(for name: String) -> String? {
        let words = tokens(in: name)
        guard !words.isEmpty else { return nil }

        var pieces: [(text: String, isChinese: Bool)] = []
        var index = 0
        var matchedAny = false
        while index < words.count {
            var matched = false
            for length in stride(from: min(maxPhraseLength, words.count - index), through: 1, by: -1) {
                let phrase = words[index..<(index + length)].map(\.key).joined(separator: " ")
                if let chinese = lookup(phrase) {
                    pieces.append((chinese, true))
                    index += length
                    matched = true
                    matchedAny = true
                    break
                }
            }
            if !matched {
                let word = words[index]
                if !skipped.contains(word.key) {
                    pieces.append((word.original, false))
                }
                index += 1
            }
        }
        guard matchedAny else { return nil }

        // Chinese runs together; English words keep spaces, with a space where the two meet.
        var result = ""
        var lastWasChinese: Bool?
        for piece in pieces {
            if let last = lastWasChinese, !(last && piece.isChinese) {
                result += " "
            }
            result += piece.text
            lastWasChinese = piece.isChinese
        }
        return result
    }

    private struct Word {
        let original: String
        /// Lowercased, curly apostrophes made straight.
        let key: String
    }

    /// Words and hyphenated parts ("Butter-Washed" → "butter", "washed"), keeping apostrophes.
    private static func tokens(in name: String) -> [Word] {
        let pattern = #"[\p{L}\p{N}]+(?:['’][\p{L}]+)*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = name as NSString
        return regex.matches(in: name, range: NSRange(location: 0, length: text.length)).map {
            let original = text.substring(with: $0.range)
            return Word(original: original, key: original.lowercased().replacingOccurrences(of: "’", with: "'"))
        }
    }

    /// Exact phrase, or its singular ("bourbons" → "bourbon", "cherries" → "cherry").
    private static func lookup(_ phrase: String) -> String? {
        if let hit = terms[phrase] { return hit }
        if phrase.hasSuffix("ies"), let hit = terms[String(phrase.dropLast(3)) + "y"] { return hit }
        if phrase.hasSuffix("es"), let hit = terms[String(phrase.dropLast(2))] { return hit }
        if phrase.hasSuffix("s"), let hit = terms[String(phrase.dropLast())] { return hit }
        return nil
    }

    /// Filler words that read better left out in Chinese.
    private static let skipped: Set<String> = ["of", "the", "a", "an", "with", "and", "fresh", "freshly", "squeezed"]

    private static let maxPhraseLength = 4

    private static let terms: [String: String] = [
        // Spirits
        "whiskey": "威士忌", "whisky": "威士忌", "bourbon": "波本", "rye": "黑麦威士忌", "rye whiskey": "黑麦威士忌",
        "scotch": "苏格兰威士忌", "scotch whisky": "苏格兰威士忌", "single malt": "单一麦芽", "blended scotch": "调和苏格兰威士忌",
        "islay": "艾雷岛", "irish whiskey": "爱尔兰威士忌", "japanese whisky": "日本威士忌",
        "gin": "金酒", "london dry gin": "伦敦干金酒", "london dry": "伦敦干型", "old tom gin": "老汤姆金酒", "old tom": "老汤姆",
        "sloe gin": "黑刺李金酒", "genever": "杜松子酒",
        "vodka": "伏特加", "rum": "朗姆酒", "white rum": "白朗姆", "light rum": "白朗姆", "aged rum": "陈年朗姆",
        "dark rum": "黑朗姆", "gold rum": "金朗姆", "spiced rum": "香料朗姆", "overproof rum": "高度朗姆",
        "rhum agricole": "农业朗姆", "agricole": "农业朗姆", "cachaça": "卡沙夏", "cachaca": "卡沙夏",
        "tequila": "龙舌兰", "blanco tequila": "银龙舌兰", "blanco": "银", "reposado": "微陈", "añejo": "陈年", "anejo": "陈年",
        "mezcal": "梅斯卡尔", "brandy": "白兰地", "cognac": "干邑", "armagnac": "雅文邑", "pisco": "皮斯科",
        "calvados": "卡尔瓦多斯", "applejack": "苹果白兰地", "grappa": "格拉帕", "absinthe": "苦艾酒",
        "baijiu": "白酒", "soju": "烧酒", "shochu": "烧酎", "sake": "清酒", "aquavit": "阿夸维特",
        // Whiskey words
        "single barrel": "单桶", "small batch": "小批量", "barrel select": "精选桶", "bonded": "保税",
        "bottled in bond": "保税装瓶", "cask strength": "原桶强度", "high rye": "高黑麦",
        // Liqueurs
        "liqueur": "利口酒", "triple sec": "橙味利口酒", "orange liqueur": "橙味利口酒", "curaçao": "库拉索", "curacao": "库拉索",
        "dry curaçao": "干型库拉索", "dry curacao": "干型库拉索", "cointreau": "君度", "grand marnier": "柑曼怡",
        "chartreuse": "查特酒", "green chartreuse": "绿查特酒", "yellow chartreuse": "黄查特酒",
        "maraschino": "黑樱桃利口酒", "maraschino liqueur": "黑樱桃利口酒", "luxardo": "路萨朵",
        "amaretto": "杏仁利口酒", "coffee liqueur": "咖啡利口酒", "kahlua": "甘露", "kahlúa": "甘露",
        "st germain": "圣哲曼接骨木花利口酒", "elderflower liqueur": "接骨木花利口酒", "elderflower": "接骨木花",
        "crème de cassis": "黑加仑利口酒", "creme de cassis": "黑加仑利口酒", "crème de cacao": "可可利口酒",
        "creme de cacao": "可可利口酒", "crème de menthe": "薄荷利口酒", "creme de menthe": "薄荷利口酒",
        "crème de violette": "紫罗兰利口酒", "creme de violette": "紫罗兰利口酒", "crème de mûre": "黑莓利口酒",
        "bénédictine": "廊酒", "benedictine": "廊酒", "drambuie": "杜林标", "galliano": "加利安奴",
        "falernum": "法勒南", "allspice dram": "多香果利口酒", "frangelico": "榛子利口酒", "limoncello": "柠檬酒",
        "midori": "蜜瓜利口酒", "cherry heering": "希琳樱桃利口酒", "jägermeister": "野格", "jagermeister": "野格",
        "baileys": "百利甜",
        // Vermouth, aperitifs, amari, wine
        "vermouth": "味美思", "sweet vermouth": "甜味美思", "dry vermouth": "干味美思", "blanc vermouth": "白味美思",
        "bianco vermouth": "白味美思", "rosso vermouth": "红味美思", "carpano": "卡帕诺", "antica": "安提卡",
        "carpano antica": "卡帕诺安提卡", "antica formula": "安提卡配方", "punt e mes": "潘脱蜜", "dolin": "杜凌",
        "cocchi americano": "科奇美国佬", "lillet": "利莱", "lillet blanc": "白利莱",
        "campari": "金巴利", "aperol": "阿佩罗", "amaro": "阿玛罗", "amaro nonino": "诺尼诺阿玛罗",
        "averna": "阿维纳", "montenegro": "黑山阿玛罗", "cynar": "洋蓟酒", "fernet": "菲奈特", "fernet branca": "菲奈特布兰卡",
        "suze": "苏兹", "sherry": "雪莉酒", "fino sherry": "菲诺雪莉", "fino": "菲诺", "amontillado": "阿蒙蒂亚多",
        "oloroso": "欧罗索", "pedro ximénez": "佩德罗希梅内斯", "pedro ximenez": "佩德罗希梅内斯", "port": "波特酒",
        "ruby port": "宝石红波特", "tawny port": "茶色波特", "madeira": "马德拉", "wine": "葡萄酒", "red wine": "红葡萄酒",
        "white wine": "白葡萄酒",
        // Bitters
        "bitters": "苦精", "bitter": "苦精", "angostura": "安高天娜", "angostura bitters": "安高天娜苦精",
        "aromatic bitters": "芳香苦精", "orange bitters": "橙味苦精", "peychaud's": "贝秀", "peychauds": "贝秀",
        "peychaud's bitters": "贝秀苦精", "chocolate bitters": "巧克力苦精", "mole bitters": "墨西哥巧克力苦精",
        "celery bitters": "芹菜苦精", "grapefruit bitters": "西柚苦精", "saline": "盐水", "saline solution": "盐水",
        // Citrus and acids
        "lemon": "柠檬", "lime": "青柠", "lemon juice": "柠檬汁", "lime juice": "青柠汁", "grapefruit": "西柚",
        "grapefruit juice": "西柚汁", "orange": "橙", "orange juice": "橙汁", "yuzu": "柚子", "citric acid": "柠檬酸",
        "malic acid": "苹果酸", "verjus": "酸葡萄汁", "shrub": "果醋糖浆", "vinegar": "醋",
        // Sweeteners
        "syrup": "糖浆", "simple syrup": "糖浆", "simple": "糖浆", "rich syrup": "浓糖浆", "rich simple syrup": "浓糖浆",
        "demerara": "德梅拉拉糖", "demarara": "德梅拉拉糖", "demerara syrup": "德梅拉拉糖浆", "sugar": "糖",
        "sugar cube": "方糖", "brown sugar": "红糖", "honey": "蜂蜜", "honey syrup": "蜂蜜糖浆", "agave": "龙舌兰",
        "agave syrup": "龙舌兰糖浆", "agave nectar": "龙舌兰糖浆", "maple syrup": "枫糖浆", "grenadine": "红石榴糖浆",
        "orgeat": "杏仁糖浆", "cinnamon syrup": "肉桂糖浆", "ginger syrup": "姜糖浆", "vanilla syrup": "香草糖浆",
        "passion fruit syrup": "百香果糖浆", "raspberry syrup": "覆盆子糖浆", "cordial": "浓缩糖浆", "gomme": "胶糖浆",
        // Juices and fresh
        "juice": "汁", "pineapple": "菠萝", "pineapple juice": "菠萝汁", "cranberry juice": "蔓越莓汁", "cranberry": "蔓越莓",
        "tomato juice": "番茄汁", "apple juice": "苹果汁", "passion fruit": "百香果", "mango": "芒果", "watermelon": "西瓜",
        "strawberry": "草莓", "raspberry": "覆盆子", "blackberry": "黑莓", "peach": "桃", "cucumber": "黄瓜",
        "mint": "薄荷", "mint leaves": "薄荷叶", "basil": "罗勒", "rosemary": "迷迭香", "thyme": "百里香", "sage": "鼠尾草",
        "ginger": "姜", "chili": "辣椒", "jalapeño": "墨西哥辣椒", "jalapeno": "墨西哥辣椒", "celery": "芹菜",
        "coconut water": "椰子水", "coconut": "椰子", "espresso": "意式浓缩咖啡", "coffee": "咖啡", "cold brew": "冷萃咖啡",
        "tea": "茶", "green tea": "绿茶", "earl grey": "伯爵茶", "matcha": "抹茶",
        // Mixers and bubbles
        "soda": "苏打水", "soda water": "苏打水", "club soda": "苏打水", "sparkling water": "气泡水", "tonic": "汤力水",
        "tonic water": "汤力水", "ginger beer": "姜汁啤酒", "ginger ale": "姜汁汽水", "cola": "可乐", "coke": "可乐",
        "lemonade": "柠檬水", "champagne": "香槟", "prosecco": "普罗赛克", "cava": "卡瓦", "sparkling wine": "起泡酒",
        "beer": "啤酒",
        // Dairy and texture
        "egg": "鸡蛋", "egg white": "蛋清", "egg yolk": "蛋黄", "whole egg": "全蛋", "cream": "奶油", "heavy cream": "淡奶油",
        "milk": "牛奶", "butter": "黄油", "brown butter": "焦化黄油", "coconut cream": "椰浆", "coconut milk": "椰奶",
        "aquafaba": "鹰嘴豆水", "yogurt": "酸奶",
        // Methods
        "washed": "洗", "fat washed": "油洗", "butter washed": "黄油洗", "infused": "浸泡", "smoked": "烟熏",
        "clarified": "澄清", "barrel aged": "桶陈", "house made": "自制", "homemade": "自制", "spiced": "香料",
        // Garnishes
        "peel": "皮", "twist": "皮卷", "zest": "皮屑", "wheel": "片", "wedge": "角", "slice": "片",
        "lemon twist": "柠檬皮卷", "lemon peel": "柠檬皮", "orange twist": "橙皮卷", "orange peel": "橙皮",
        "lime wheel": "青柠片", "lime wedge": "青柠角", "cherry": "樱桃", "maraschino cherry": "酒浸樱桃",
        "luxardo cherry": "路萨朵樱桃", "brandied cherry": "白兰地樱桃", "olive": "橄榄", "nutmeg": "肉豆蔻",
        "cinnamon": "肉桂", "salt": "盐", "sea salt": "海盐", "salt rim": "盐边", "sugar rim": "糖边", "rim": "杯边",
        "ice": "冰", "star anise": "八角", "clove": "丁香", "vanilla": "香草", "cocoa": "可可", "chocolate": "巧克力",
        // Common brands
        "jack daniel's": "杰克丹尼", "jack daniels": "杰克丹尼", "jim beam": "金宾", "maker's mark": "美格",
        "makers mark": "美格", "wild turkey": "威凤凰", "buffalo trace": "水牛足迹", "woodford reserve": "活福珍藏",
        "four roses": "四玫瑰", "knob creek": "诺布溪", "bulleit": "布莱特", "rittenhouse": "里滕豪斯",
        "jameson": "尊美醇", "johnnie walker": "尊尼获加", "macallan": "麦卡伦", "laphroaig": "拉弗格",
        "lagavulin": "乐加维林", "ardbeg": "雅柏", "glenfiddich": "格兰菲迪", "glenlivet": "格兰威特",
        "monkey shoulder": "三只猴子", "suntory": "三得利", "hibiki": "响", "yamazaki": "山崎", "nikka": "日果",
        "bacardi": "百加得", "havana club": "哈瓦那俱乐部", "plantation": "种植园", "appleton": "阿普尔顿",
        "hennessy": "轩尼诗", "rémy martin": "人头马", "remy martin": "人头马", "martell": "马爹利",
        "tanqueray": "添加利", "beefeater": "必富达", "hendrick's": "亨利爵士", "hendricks": "亨利爵士",
        "bombay sapphire": "孟买蓝宝石", "monkey 47": "猴王47", "patrón": "培恩", "patron": "培恩",
        "don julio": "唐胡里奥", "jose cuervo": "豪帅快活", "del maguey": "德尔玛盖", "grey goose": "灰雁",
        "absolut": "绝对", "smirnoff": "斯米诺", "belvedere": "雪树", "martini": "马天尼", "cinzano": "仙山露",
        "noilly prat": "诺丽普拉",
        // Counts
        "two": "两种", "three": "三种", "house": "自制",
    ]
}
