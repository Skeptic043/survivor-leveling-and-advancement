import java.io.FileReader;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

public final class NativeStoreBenchmark {
    private static Method method(Class<?> type, String name, int count) {
        for (Method method : type.getMethods()) if (method.getName().equals(name) && method.getParameterCount() == count) return method;
        throw new IllegalStateException(name);
    }
    private static Object run(Object thread, Object closure) throws Exception {
        Object[] result = (Object[]) method(thread.getClass(), "pcall", 2).invoke(thread, closure, new Object[0]);
        if (!Boolean.TRUE.equals(result[0])) throw new RuntimeException(String.valueOf(result[1]));
        return result.length > 1 ? result[1] : null;
    }
    public static void main(String[] args) throws Exception {
        Class<?> platformClass = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform = platformClass.getConstructor().newInstance();
        Object environment = method(platformClass, "newEnvironment", 0).invoke(platform);
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> threadClass = Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object thread = null;
        for (java.lang.reflect.Constructor<?> constructor : threadClass.getConstructors()) {
            if (constructor.getParameterCount() == 2 && constructor.getParameterTypes()[1].isAssignableFrom(tableClass)) thread = constructor.newInstance(platform, environment);
        }
        java.lang.reflect.Field owner = threadClass.getDeclaredField("debugOwnerThread");
        owner.setAccessible(true);
        owner.set(thread, Thread.currentThread());
        Method rawset = environment.getClass().getMethod("rawset", Object.class, Object.class);
        Class<?> javaFunction = Class.forName("se.krka.kahlua.vm.JavaFunction");
        Class<?> frameClass = Class.forName("se.krka.kahlua.vm.LuaCallFrame");
        Method push = method(frameClass, "push", 1);
        Method get = method(frameClass, "get", 1);
        for (String name : new String[] { "benchClock", "benchMemory", "print" }) {
            Object function = Proxy.newProxyInstance(javaFunction.getClassLoader(), new Class<?>[] { javaFunction }, (proxy, called, parameters) -> {
                if (name.equals("print")) {
                    System.out.println(get.invoke(parameters[0], 0));
                    return 0;
                }
                Runtime runtime = Runtime.getRuntime();
                double value = name.equals("benchClock") ? System.nanoTime() / 1e6 : runtime.totalMemory() - runtime.freeMemory();
                push.invoke(parameters[0], value);
                return 1;
            });
            rawset.invoke(environment, name, function);
        }
        Method load = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadis", java.io.Reader.class, String.class, tableClass);
        for (int i = 1; i < args.length; i += 2) {
            try (FileReader file = new FileReader(args[i + 1])) {
                rawset.invoke(environment, args[i], run(thread, load.invoke(null, file, args[i], environment)));
            }
        }
        try (FileReader file = new FileReader(args[0])) {
            run(thread, load.invoke(null, file, "native store benchmark", environment));
        }
    }
}
