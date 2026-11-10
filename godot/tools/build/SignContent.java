// Use the existing APK signing identity without exporting its private key.
import java.nio.file.*;
import java.security.*;
import java.util.Base64;
public class SignContent {
  public static void main(String[] args) throws Exception {
    char[] password = System.getenv("GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD").toCharArray();
    KeyStore store = KeyStore.getInstance(Path.of(System.getenv("GODOT_ANDROID_KEYSTORE_RELEASE_PATH")).toFile(), password);
    String alias = System.getenv("GODOT_ANDROID_KEYSTORE_RELEASE_USER");
    var certificate = store.getCertificate(alias);
    String actual = java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
    String expected = System.getenv("ANDROID_SIGNING_CERT_SHA256").replace(":", "").toLowerCase();
    if (!MessageDigest.isEqual(actual.getBytes(),expected.getBytes())) throw new SecurityException("APK certificate mismatch");
    if (!certificate.getPublicKey().getAlgorithm().equals("RSA")) throw new SecurityException("Content signature requires existing RSA identity");
    if (args[0].equals("public")) {
      String pem = "-----BEGIN PUBLIC KEY-----\n" + Base64.getMimeEncoder(64,new byte[]{10}).encodeToString(certificate.getPublicKey().getEncoded()) + "\n-----END PUBLIC KEY-----\n";
      Files.writeString(Path.of(args[1]),pem);
    } else if (args[0].equals("sign")) {
      Signature signature=Signature.getInstance("SHA256withRSA"); signature.initSign((PrivateKey)store.getKey(alias,password));
      signature.update(Files.readAllBytes(Path.of(args[1]))); Files.write(Path.of(args[2]),signature.sign());
    } else throw new IllegalArgumentException("public or sign required");
    java.util.Arrays.fill(password,'\0');
  }
}
