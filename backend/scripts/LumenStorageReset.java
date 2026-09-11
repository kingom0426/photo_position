import com.aliyun.oss.*;
import com.aliyun.oss.common.auth.DefaultCredentialProvider;
import com.aliyun.oss.common.comm.SignVersion;
import com.aliyun.oss.model.*;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.io.*;
import java.security.MessageDigest;
import java.util.*;

/** One-off operations tool. Only exact Lumen upload keys under photos/ are eligible. */
class LumenStorageReset {
    static final String PREFIX = "photos/";
    static final String KEY_PATTERN = "photos/[0-9]{4}/[0-9]{2}/[^/]+/[0-9a-fA-F-]{36}-(original|display|thumbnail|avatar)\\.(jpg|png|webp|heic|heif)";

    public static void main(String[] args) throws Exception {
        if (args.length < 2) throw new IllegalArgumentException("inventory|backup|delete, private backup directory required");
        String mode = args[0];
        Path root = Path.of(args[1]).toAbsolutePath().normalize();
        if (!root.toString().startsWith(Path.of("work/data-reset-backups").toAbsolutePath().normalize() + "/")) {
            throw new IllegalArgumentException("Backup must be inside the dedicated private backup directory");
        }
        Properties config = new Properties();
        try (Reader reader = Files.newBufferedReader(Path.of("backend/.env.local"))) { config.load(reader); }
        String bucket = config.getProperty("OSS_BUCKET");
        String region = config.getProperty("OSS_REGION").replaceFirst("^oss-", "");
        String endpoint = config.getProperty("OSS_ENDPOINT", "").trim();
        if (endpoint.isBlank()) endpoint = "https://" + config.getProperty("OSS_REGION") + ".aliyuncs.com";
        if (!endpoint.startsWith("https://")) throw new IllegalArgumentException("HTTPS endpoint required");
        var settings = new ClientBuilderConfiguration();
        settings.setSignatureVersion(SignVersion.V4);
        OSS oss = OSSClientBuilder.create().endpoint(endpoint).region(region).clientConfiguration(settings)
                .credentialsProvider(new DefaultCredentialProvider(config.getProperty("OSS_ACCESS_KEY_ID"), config.getProperty("OSS_ACCESS_KEY_SECRET"))).build();
        try {
            var objects = list(oss, bucket);
            long bytes = objects.stream().mapToLong(OSSObjectSummary::getSize).sum();
            long unexpected = objects.stream().filter(o -> !o.getKey().matches(KEY_PATTERN)).count();
            System.out.printf("Lumen photos prefix: %d objects, %d bytes; unexpected key formats: %d%n", objects.size(), bytes, unexpected);
            if (mode.equals("inventory")) return;
            if (unexpected > 0) throw new IllegalStateException("Unexpected key formats: stop for scope review; nothing deleted");
            Path manifest = root.resolve("oss-manifest.tsv");
            if (mode.equals("backup")) {
                Files.createDirectories(root.resolve("objects"));
                Files.setPosixFilePermissions(root, PosixFilePermissions.fromString("rwx------"));
                if (Files.exists(manifest)) throw new IllegalStateException("Existing manifest: refuse to overwrite");
                List<String> lines = new ArrayList<>();
                lines.add("bucket\t" + bucket);
                int number = 0;
                for (var object : objects) {
                    String filename = String.format("objects/%06d.bin", ++number);
                    Path destination = root.resolve(filename);
                    var request = new GetObjectRequest(bucket, object.getKey());
                    request.setMatchingETagConstraints(List.of(object.getETag()));
                    oss.getObject(request, destination.toFile());
                    Files.setPosixFilePermissions(destination, PosixFilePermissions.fromString("rw-------"));
                    if (Files.size(destination) != object.getSize()) throw new IllegalStateException("Backup size mismatch");
                    lines.add(Base64.getEncoder().encodeToString(object.getKey().getBytes(java.nio.charset.StandardCharsets.UTF_8))
                            + "\t" + object.getETag() + "\t" + object.getSize() + "\t" + digest(destination) + "\t" + filename);
                    if (number % 20 == 0) System.out.println("Backed up objects: " + number);
                }
                Files.write(manifest, lines, StandardOpenOption.CREATE_NEW);
                Files.setPosixFilePermissions(manifest, PosixFilePermissions.fromString("rw-------"));
                System.out.println("Backup complete: " + number + " objects; SHA-256 recorded for each file");
            } else if (mode.equals("delete")) {
                if (args.length != 3 || !args[2].equals("CONFIRM_LUMEN_PHOTOS_RESET")) throw new IllegalArgumentException("Explicit confirmation required");
                List<String> lines = Files.readAllLines(manifest);
                if (!lines.get(0).equals("bucket\t" + bucket)) throw new IllegalStateException("Backup bucket mismatch");
                Map<String, String[]> backedUp = new LinkedHashMap<>();
                for (String line : lines.subList(1, lines.size())) {
                    String[] fields = line.split("\t");
                    String key = new String(Base64.getDecoder().decode(fields[0]), java.nio.charset.StandardCharsets.UTF_8);
                    Path file = root.resolve(fields[4]).normalize();
                    if (!key.matches(KEY_PATTERN) || !file.startsWith(root.resolve("objects"))
                            || Files.size(file) != Long.parseLong(fields[2]) || !digest(file).equals(fields[3])) {
                        throw new IllegalStateException("Backup validation failed; nothing deleted");
                    }
                    backedUp.put(key, fields);
                }
                // Validate the entire live inventory before any deletion. New/changed objects abort safely.
                for (var object : objects) {
                    var fields = backedUp.get(object.getKey());
                    if (fields == null || !fields[1].equals(object.getETag()) || Long.parseLong(fields[2]) != object.getSize()) {
                        throw new IllegalStateException("Live data differs from backup; nothing deleted");
                    }
                }
                int count = 0;
                for (var object : objects) {
                    oss.deleteObject(bucket, object.getKey());
                    count++;
                    if (count % 20 == 0) System.out.println("Removed backed-up objects: " + count);
                }
                long remaining = list(oss, bucket).size();
                System.out.println("Removed objects: " + count + "; remaining in photos/: " + remaining);
                if (remaining != 0) throw new IllegalStateException("Photos prefix not empty");
            } else throw new IllegalArgumentException("Unknown mode");
        } finally { oss.shutdown(); }
    }

    static List<OSSObjectSummary> list(OSS oss, String bucket) {
        List<OSSObjectSummary> result = new ArrayList<>();
        String token = null;
        do {
            var request = new ListObjectsV2Request(bucket).withPrefix(PREFIX).withMaxKeys(1000);
            request.setContinuationToken(token);
            var page = oss.listObjectsV2(request);
            result.addAll(page.getObjectSummaries());
            token = page.isTruncated() ? page.getNextContinuationToken() : null;
        } while (token != null);
        return result;
    }

    static String digest(Path file) throws Exception {
        MessageDigest hash = MessageDigest.getInstance("SHA-256");
        try (InputStream in = Files.newInputStream(file)) {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) != -1) hash.update(buf, 0, n);
        }
        return HexFormat.of().formatHex(hash.digest());
    }
}
