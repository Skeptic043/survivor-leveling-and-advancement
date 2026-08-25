import java.io.FileReader;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public final class KahluaRunner {
    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message);
    }
    private static String count(Object assertions) {
        if (assertions instanceof Number && ((Number) assertions).doubleValue() == ((Number) assertions).longValue()) return Long.toString(((Number) assertions).longValue());
        return String.valueOf(assertions);
    }
    private static Method method(Class<?> type, String name, int parameterCount) {
        for (Method candidate : type.getMethods()) {
            if (candidate.getName().equals(name) && candidate.getParameterTypes().length == parameterCount) return candidate;
        }
        throw new IllegalStateException("Missing method: " + name);
    }
    private static Method rawsetMethod(Class<?> type) {
        for (Method candidate : type.getMethods()) {
            Class<?>[] parameters = candidate.getParameterTypes();
            if (candidate.getName().equals("rawset") && parameters.length == 2 && parameters[0].isAssignableFrom(String.class)) return candidate;
        }
        throw new IllegalStateException("Missing string-key rawset");
    }
    private static Object run(Object thread, Object closure, String label) throws Exception {
        Method pcall = method(thread.getClass(), "pcall", 2);
        Object[] result = (Object[]) pcall.invoke(thread, closure, new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new RuntimeException(label + ": " + result[1]);
        return result.length > 1 ? result[1] : null;
    }
    public static void main(String[] args) throws Exception {
        require(args.length >= 4 && (args.length - 2) % 2 == 0, "usage: KahluaRunner <label> <spec> <global> <source> [...]");
        require(!args[0].isEmpty() && !args[1].isEmpty(), "label and spec are required");
        for (int i = 2; i < args.length; i += 2) require(!args[i].isEmpty() && !args[i + 1].isEmpty(), "global names and source paths are required");
        Class<?> platformClass = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform = platformClass.getConstructor().newInstance();
        Object environment = method(platformClass, "newEnvironment", 0).invoke(platform);
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Constructor<?> threadConstructor = null;
        for (Constructor<?> candidate : Class.forName("se.krka.kahlua.vm.KahluaThread").getConstructors()) {
            Class<?>[] parameters = candidate.getParameterTypes();
            if (parameters.length == 2 && parameters[1].isAssignableFrom(tableClass)) { threadConstructor = candidate; break; }
        }
        if (threadConstructor == null) throw new IllegalStateException("Missing KahluaThread constructor");
        Object thread = threadConstructor.newInstance(platform, environment);
        Field debugOwner = thread.getClass().getDeclaredField("debugOwnerThread");
        debugOwner.setAccessible(true);
        debugOwner.set(thread, Thread.currentThread());
        Class<?> compiler = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        Method loadis = compiler.getMethod("loadis", java.io.Reader.class, String.class, tableClass);
        Method rawset = rawsetMethod(environment.getClass());
        for (int i = 2; i < args.length; i += 2) {
            try (FileReader source = new FileReader(args[i + 1])) {
                Object closure = loadis.invoke(null, source, args[i], environment);
                rawset.invoke(environment, args[i], run(thread, closure, args[i]));
            }
        }
        try (FileReader specReader = new FileReader(args[1])) {
            Object spec = loadis.invoke(null, specReader, args[0], environment);
            Object assertions = run(thread, spec, args[0]);
            System.out.println(args[0] + ": 1 suite, " + count(assertions) + " assertions");
        }
    }
}
