import java.lang.reflect.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.Function;
import java.util.function.Consumer;
import java.util.regex.*;
import java.util.stream.Collectors;

public final class TranslationValidator {
    private static int checks;
    private static final Set<String> LOCALES = new TreeSet<>(Arrays.asList(
        "EN", "ES", "ES_MX", "ES_CL", "AR", "RU", "PTBR", "PT", "CN", "CH", "KO", "TR", "FR", "PL", "DE", "UA",
        "CA", "CS", "DA", "FI", "HU", "ID", "IT", "JP", "NL", "NO", "RO", "TH"));
    private static final Set<String> FILES = new TreeSet<>(Arrays.asList("IG_UI.json", "Sandbox.json"));
    private static void check(boolean ok, String message) {
        checks++;
        if (!ok) throw new IllegalStateException(message);
    }
    private static Map<String, Object> parse(String text) throws Exception {
        Class<?> config = Class.forName("org.json.JSONParserConfiguration");
        Object strict = config.getMethod("withStrictMode", boolean.class).invoke(config.getConstructor().newInstance(), true);
        Object json = Class.forName("org.json.JSONObject").getConstructor(String.class, config).newInstance(text, strict);
        return (Map<String, Object>) json.getClass().getMethod("toMap").invoke(json);
    }
    private static Map<String, Object> read(Path file) throws Exception {
        String text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(Files.readAllBytes(file))).toString();
        return parse(text);
    }
    private static Map<String, Integer> tokens(String text, String regex) {
        Map<String, Integer> result = new TreeMap<>();
        Matcher matches = Pattern.compile(regex).matcher(text);
        while (matches.find()) result.merge(matches.group(), 1, Integer::sum);
        return result;
    }
    private static void contract(String english, String translated, String label) {
        check(!translated.trim().isEmpty(), label + " is empty");
        check(tokens(english, "%(?:%|[1-9][0-9]*)").equals(tokens(translated, "%(?:%|[1-9][0-9]*)")), label + " placeholder/percent mismatch");
        check(tokens(english, "<[^>]+>").equals(tokens(translated, "<[^>]+>")), label + " markup mismatch");
        check(english.replaceAll("%(?:%|[1-9][0-9]*)", "").chars().filter(c -> c == '%').count()
            == translated.replaceAll("%(?:%|[1-9][0-9]*)", "").chars().filter(c -> c == '%').count(), label + " unexpected percent token");
        check(!translated.contains(";") && !translated.contains("\u2014"), label + " prohibited public punctuation");
    }
    private static boolean sharedEnglish(String key, String value) {
        return key.equals("IGUI_SLA_ModOptions_Title") || key.equals("Sandbox_SLA")
            || key.equals("IGUI_SLA_StatusAP") || key.equals("IGUI_SLA_LevelGain_AP")
            || key.equals("IGUI_SLA_Admin_Button") && value.equals("Admin")
            || key.equals("Sandbox_SLA_AllotmentMode_values_option1") && value.equals("Global")
            || key.matches("Sandbox_SLA_PerSkillLimit_option(?:[2-9]|1[0-2])")
            || key.startsWith("Sandbox_SLA_PerSkill_"); // Checked against vanilla below.
    }
    private static void rejects(String label, Checked action) throws Exception {
        boolean rejected = false;
        try { action.run(); } catch (Exception expected) { rejected = true; }
        check(rejected, "Validator accepted invalid " + label);
    }
    private interface Checked { void run() throws Exception; }
    private static Set<String> children(Path directory) throws Exception {
        try (var paths = Files.list(directory)) {
            return paths.map(p -> p.getFileName().toString()).collect(Collectors.toCollection(TreeSet::new));
        }
    }
    private static String vanillaKey(String id) {
        if (id.equals("Lightfoot")) id = "Lightfooted";
        if (id.equals("Sneak")) id = "Sneaking";
        if (id.equals("PlantScavenging")) id = "Foraging";
        return "IGUI_perks_" + id;
    }
    private static String lua(String value) {
        return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r") + "\"";
    }
    private static void verifyPerkLuaAccess() throws Exception {
        Class<?> platformType = Class.forName("se.krka.kahlua.vm.Platform");
        Class<?> tableType = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Object platform = Class.forName("se.krka.kahlua.j2se.J2SEPlatform").getConstructor().newInstance();
        Object environment = platform.getClass().getMethod("newEnvironment").invoke(platform);
        Class<?> managerType = Class.forName("se.krka.kahlua.converter.KahluaConverterManager");
        Object manager = managerType.getConstructor().newInstance();
        Class<?> exposerType = Class.forName("zombie.Lua.LuaManager$Exposer");
        Object exposer = exposerType.getConstructor(managerType, platformType, tableType).newInstance(manager, platform, environment);
        Class<?> perkType = Class.forName("zombie.characters.skills.PerkFactory$Perk");
        exposerType.getMethod("setExposed", Class.class).invoke(exposer, perkType);
        exposerType.getMethod("exposeLikeJava", Class.class, tableType).invoke(exposer, perkType, environment);
        Object perk = perkType.getConstructor(String.class).newInstance("Strength");
        perkType.getField("name").set(perk, "\u529b\u91cf");
        environment.getClass().getMethod("rawset", Object.class, Object.class).invoke(environment, "perk", perk);
        environment.getClass().getMethod("rawset", Object.class, Object.class).invoke(environment, "expectedName", "\u529b\u91cf");
        Class<?> threadType = Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object thread = threadType.getConstructor(platformType, tableType).newInstance(platform, environment);
        Field owner = threadType.getDeclaredField("debugOwnerThread");
        owner.setAccessible(true);
        owner.set(thread, Thread.currentThread());
        String source = "assert(type(perk.getId) == 'function' and perk:getId() == 'Strength', 'getId'); "
            + "assert(type(perk.getName) == 'function' and perk:getName() == expectedName, 'getName'); "
            + "assert(type(perk.isCustom) == 'function' and perk:isCustom() == false, 'isCustom false'); "
            + "perk:setCustom(); assert(perk:isCustom() == true, 'isCustom true'); return true";
        Object closure = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
            .getMethod("loadis", java.io.Reader.class, String.class, tableType)
            .invoke(null, new java.io.StringReader(source), "native Perk Lua access", environment);
        Object[] result = (Object[]) threadType.getMethod("pcall", Object.class, Object[].class)
            .invoke(thread, closure, new Object[0]);
        check(Boolean.TRUE.equals(result[0]) && Boolean.TRUE.equals(result[1]), "native Perk getters/custom flag accessible from Kahlua: " + Arrays.toString(result));
    }
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]), game = Path.of(args[1]);
        Path mod = root.resolve("Contents/mods/SurvivorLevelingAdvancement/42.20");
        Path translations = mod.resolve("media/lua/shared/Translate");
        Path nativeTranslations = game.resolve("media/lua/shared/Translate");
        Set<String> settingsLocales = new TreeSet<>();
        for (String locale : children(nativeTranslations)) {
            if (!locale.equals("STREW") && Files.isRegularFile(nativeTranslations.resolve(locale).resolve("language.json"))) {
                settingsLocales.add(locale);
            }
        }
        check(settingsLocales.equals(LOCALES), "Standard game Settings languages changed: " + settingsLocales);
        rejects("duplicate key", () -> parse("{\"x\":\"a\",\"x\":\"b\"}"));
        rejects("invalid JSON", () -> parse("{\"x\":\"a\",}"));
        rejects("changed placeholder", () -> contract("%1 %2", "%1 %3", "fixture"));
        rejects("duplicated placeholder", () -> contract("%1 %2", "%1 %1 %2", "fixture"));
        rejects("literal percent", () -> contract("%%", "%", "fixture"));
        rejects("markup", () -> contract("<LINE>%1", "%1", "fixture"));
        rejects("empty string", () -> contract("hello", " ", "fixture"));
        rejects("invalid UTF-8", () -> StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(new byte[]{(byte)0xc3, 0x28})));
        contract("%1 %2 %% <LINE>", "%2 %1 %% <LINE>", "reordered placeholders");
        check(children(translations).equals(LOCALES), "Missing/unexpected locale folders: " + children(translations));
        Map<String, Map<String, Object>> baseline = new HashMap<>();
        for (String file : FILES) baseline.put(file, read(translations.resolve("EN").resolve(file)));
        Map<String, Map<String, Object>> uiByLocale = new TreeMap<>();
        for (String locale : LOCALES) {
            Path folder = translations.resolve(locale);
            check(children(folder).equals(FILES), locale + " has missing/unexpected files");
            Map<String, Object> vanilla = read(game.resolve("media/lua/shared/Translate/EN/IG_UI.json"));
            for (Map.Entry<String, Object> entry : read(game.resolve("media/lua/shared/Translate/" + locale + "/IG_UI.json")).entrySet()) {
                if (entry.getValue() instanceof String && !((String) entry.getValue()).isEmpty()) vanilla.put(entry.getKey(), entry.getValue());
            }
            for (String file : FILES) {
                Map<String, Object> values = read(folder.resolve(file)), english = baseline.get(file);
                check(values.keySet().equals(english.keySet()), locale + "/" + file + " key mismatch");
                for (String key : english.keySet()) {
                    check(values.get(key) instanceof String, locale + "/" + key + " is not a string");
                    String value = (String) values.get(key), source = (String) english.get(key);
                    contract(source, value, locale + "/" + key);
                    if (!locale.equals("EN")) check(!value.equals(source) || sharedEnglish(key, value), locale + "/" + key + " untranslated English");
                    if (key.startsWith("Sandbox_SLA_PerSkill_")) {
                        String expected = (String) vanilla.get(vanillaKey(key.substring("Sandbox_SLA_PerSkill_".length())));
                        check(value.equals(expected), locale + "/" + key + " differs from vanilla skill name");
                    }
                }
                if (file.equals("IG_UI.json")) uiByLocale.put(locale, values);
            }
        }
        // Reflection exercises the installed loader and formatting without starting a game or touching user files.
        Class<?> translator = Class.forName("zombie.core.Translator"), language = Class.forName("zombie.core.Language");
        Constructor<?> languageCtor = language.getDeclaredConstructor(String.class, String.class, String.class, boolean.class);
        languageCtor.setAccessible(true);
        Method loader = translator.getDeclaredMethod("tryFillMapFromFile", String.class, String.class, Map.class, language, Function.class);
        loader.setAccessible(true);
        Method format = translator.getDeclaredMethod("formatFixer", String.class);
        format.setAccessible(true);
        Function<String, String> fixer = value -> { try { return (String) format.invoke(null, value); } catch (Exception e) { throw new RuntimeException(e); } };
        Method getText = translator.getMethod("getText", String.class, Object[].class);
        Map<String, Map<String, String>> maps = (Map<String, Map<String, String>>) translator.getField("BY_NAME").get(null);
        for (String locale : LOCALES) {
            Object current = languageCtor.newInstance(locale, locale, "EN", false);
            translator.getField("language").set(null, current);
            for (String file : FILES) {
                String category = file.replace(".json", "");
                Map<String, String> map = maps.get(category);
                check(map != null, "Translator category " + category);
                map.clear();
                loader.invoke(null, mod.toString(), category, map, current, fixer);
                check(map.size() == baseline.get(file).size(), locale + " game loader key count " + category);
                String key = category.equals("IG_UI") ? "IGUI_SLA_Admin_Refresh" : "Sandbox_SLA_AllotmentMode_values_option2";
                String expected = (String) read(translations.resolve(locale).resolve(file)).get(key);
                check(expected.equals(getText.invoke(null, key, new Object[0])), locale + " Translator.getText " + key);
            }
            String translated = (String) uiByLocale.get(locale).get("IGUI_SLA_StatusLevel");
            check(translated.replace("%1", "7").equals(getText.invoke(null, "IGUI_SLA_StatusLevel", new Object[]{7})), locale + " argument substitution");
            String percent = (String) uiByLocale.get(locale).get("IGUI_SLA_WatchOption");
            check(percent.replace("%%", "%").equals(getText.invoke(null, "IGUI_SLA_WatchOption", new Object[0])), locale + " literal percent rendering");
            Map<String, String> ui = maps.get("IG_UI");
            ui.clear();
            Path fallbackRoot = root.resolve("tests/.build/fallback");
            Path fallbackFile = fallbackRoot.resolve("media/lua/shared/Translate/" + locale + "/IG_UI.json");
            Files.createDirectories(fallbackFile.getParent());
            Files.writeString(fallbackFile, "{\"IGUI_SLA_StatusLevel\":" + lua(translated) + "}");
            Consumer<Object> loadStack = item -> {
                try {
                    String name = (String) language.getMethod("name").invoke(item);
                    String directory = name.equals("EN") ? mod.toString() : fallbackRoot.toString();
                    loader.invoke(null, directory, "IG_UI", ui, item, fixer);
                } catch (Exception e) { throw new RuntimeException(e); }
            };
            translator.getMethod("forLanguageStack", Consumer.class).invoke(null, loadStack);
            check("Refresh".equals(getText.invoke(null, "IGUI_SLA_Admin_Refresh", new Object[0])), locale + " missing-key EN fallback");
            check(translated.replace("%1", "7").equals(getText.invoke(null, "IGUI_SLA_StatusLevel", new Object[]{7})), locale + " fallback retains existing translation");
        }
        Path fixture = root.resolve("tests/.build/locale-ui-fixture.lua");
        StringBuilder data = new StringBuilder("return {\n");
        for (String locale : LOCALES) {
            data.append('[').append(lua(locale)).append("] = {\n");
            for (Map.Entry<String, Object> entry : uiByLocale.get(locale).entrySet()) data.append('[').append(lua(entry.getKey())).append("] = ").append(lua((String) entry.getValue())).append(",\n");
            data.append("},\n");
        }
        Files.writeString(fixture, data.append("}\n"));
        StringBuilder skills = new StringBuilder("return {\n");
        for (String locale : Arrays.asList("EN", "ES", "UA", "CN")) {
            skills.append('[').append(lua(locale)).append("] = {\n");
            for (Map.Entry<String, Object> entry : read(game.resolve("media/lua/shared/Translate/" + locale + "/IG_UI.json")).entrySet()) {
                if (entry.getKey().startsWith("IGUI_perks_")) skills.append('[').append(lua(entry.getKey())).append("] = ").append(lua((String) entry.getValue())).append(",\n");
            }
            skills.append("},\n");
        }
        Files.writeString(root.resolve("tests/.build/vanilla-skill-translations.lua"), skills.append("}\n"));
        Files.copy(game.resolve("media/lua/client/PZAPI/ModOptions.lua"),
            root.resolve("tests/.build/vanilla-mod-options.lua"), StandardCopyOption.REPLACE_EXISTING);
        verifyPerkLuaAccess();
        System.out.println("C86 translations: " + LOCALES.size() + " locales, " + checks + " assertions; installed Translator loading, substitution and fallback passed");
    }
}
