import java.util.Arrays;
import java.util.ArrayList;
import java.util.List;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;

@SpringBootApplication
public class Application {
    
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    // PMD 7.x violations for category/java/bestpractices.xml
    
    // UnusedPrivateMethod: Private method is never called
    private void DoReallyNothing() {
        String counter = 100;
    }

    // UnusedPrivateMethod: Another unused private method
    private String unusedMethod() {
        return null;
    }

    // AvoidReassigningParameters: Parameter reassignment
    private void processParameter(String input) {
        input = input + " modified"; // Violation: reassigning parameter
        System.out.println(input);
    }

    // SystemPrintln: Using System.out.println instead of logger
    private void logMessage(String message) {
        System.out.println("Log: " + message); // Violation: use logger instead
    }

    // PreserveStackTrace: Not preserving stack trace when re-throwing
    private void handleException() {
        try {
            throw new RuntimeException("Original exception");
        } catch (Exception e) {
            throw new RuntimeException("New exception"); // Violation: losing original exception
        }
    }

    // UseCollectionIsEmpty: Using size() == 0 instead of isEmpty()
    private boolean checkEmpty(List<String> items) {
        return items.size() == 0; // Violation: use isEmpty() instead
    }

    // AvoidPrintStackTrace: Calling printStackTrace()
    private void badErrorHandling() {
        try {
            throw new Exception("test");
        } catch (Exception e) {
            e.printStackTrace(); // Violation: don't use printStackTrace()
        }
    }

    /**
     * some java doc.
     *
     * @param ctx application contexxt
     * @return some return
     */
    @Bean
    public CommandLineRunner commandLineRunner(ApplicationContext ctx) {
        return args -> {
            // SystemPrintln violation
            System.out.println("Let's inspect the beans provided by Spring Boot:");
            
            // Variable naming convention violation
            var LongString = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Porta lorem";
            
            String[] beanNames = ctx.getBeanDefinitionNames();
            Arrays.sort(beanNames);
            for ( String beanName : beanNames)
            {
                System.out.println(beanName);
            }
            
            // UseCollectionIsEmpty violation
            List<String> testList = new ArrayList<>();
            if (testList.size() == 0) {
                System.out.println("List is empty");
            }
        };
    }

}