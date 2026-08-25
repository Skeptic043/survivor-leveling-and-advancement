import java.io.FileReader;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public final class KahluaRunner {
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
        Object codec = loadis.invoke(null, new FileReader(args[0]), "StateCodec", environment);
        rawsetMethod(environment.getClass()).invoke(environment, "StateCodec", run(thread, codec, "codec"));
        Object spec = loadis.invoke(null, new FileReader(args[1]), "StateCodecSpec", environment);
        Object assertions = run(thread, spec, "spec");
        System.out.println("B3 StateCodec: 1 suite, " + assertions + " assertions");
    }
}
