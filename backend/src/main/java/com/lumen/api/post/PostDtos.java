package com.lumen.api.post;

import java.util.List;
import java.util.UUID;

public final class PostDtos {
    private PostDtos() {}

    public record Author(String id, String name, String avatarUrl, String city) {}

    public record Image(
            String objectKey,
            String originalUrl,
            String displayUrl,
            String thumbnailUrl
    ) {}

    public record Metadata(
            String cameraMake,
            String cameraModel,
            String camera,
            String lens,
            Double focalLengthMm,
            Double aperture,
            Double shutterSeconds,
            Integer iso,
            Double exposureCompensation,
            String capturedAt,
            String source
    ) {}

    public record Location(
            String name,
            String city,
            String district,
            String detailedAddress,
            String privacy,
            Double latitude,
            Double longitude,
            String advice
    ) {}

    public record PostResponse(
            UUID id,
            String kind,
            UUID originalId,
            Author author,
            String title,
            String description,
            Image image,
            List<String> tags,
            boolean allowRemake,
            String shootingNotes,
            String editingNotes,
            String reusedNotes,
            String adjustedNotes,
            String assignmentNotes,
            boolean isRecommended,
            int likeCount,
            int commentCount,
            boolean liked,
            boolean planned,
            String createdAt,
            Metadata metadata,
            Location location,
            Double distanceKm
    ) {}

    public record PostList(
            List<PostResponse> items,
            int limit,
            int offset,
            boolean hasMore
    ) {}

    public record CreatePostRequest(
            String kind,
            UUID originalId,
            String title,
            String description,
            CreateImage image,
            List<String> tags,
            Boolean allowRemake,
            String shootingNotes,
            String editingNotes,
            String reusedNotes,
            String adjustedNotes,
            String assignmentNotes,
            CreateMetadata metadata,
            CreateLocation location
    ) {}

    public record CreateImage(
            String objectKey,
            String originalUrl,
            String displayObjectKey,
            String displayUrl,
            String thumbnailObjectKey,
            String thumbnailUrl
    ) {}

    public record CreateMetadata(
            String cameraMake,
            String cameraModel,
            String camera,
            String lens,
            Double focalLengthMm,
            Double aperture,
            Double shutterSeconds,
            Integer iso,
            Double exposureCompensation,
            String capturedAt,
            String source
    ) {}

    public record CreateLocation(
            String name,
            String city,
            String district,
            String detailedAddress,
            String privacy,
            Double latitude,
            Double longitude,
            String advice
    ) {}

    public record LikeResponse(boolean liked, int likeCount) {}

    public record PlanResponse(boolean planned) {}

    public record CommentAuthor(String id, String name, String avatarUrl) {}

    public record CommentResponse(
            UUID id,
            String content,
            UUID parentId,
            String createdAt,
            CommentAuthor author
    ) {}

    public record CommentList(List<CommentResponse> items) {}

    public record CreateComment(String content) {}
}
