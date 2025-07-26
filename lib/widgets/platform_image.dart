import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class PlatformImage extends StatelessWidget {
  final String? assetPath;
  final String? networkUrl;
  final Uint8List? imageData;
  final String? filePath;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? errorWidget;
  final Widget? loadingWidget;

  const PlatformImage({
    Key? key,
    this.assetPath,
    this.networkUrl,
    this.imageData,
    this.filePath,
    this.width,
    this.height,
    this.fit,
    this.errorWidget,
    this.loadingWidget,
  }) : super(key: key);

  factory PlatformImage.asset(
    String assetPath, {
    Key? key,
    double? width,
    double? height,
    BoxFit? fit,
    Widget? errorWidget,
  }) {
    return PlatformImage(
      key: key,
      assetPath: assetPath,
      width: width,
      height: height,
      fit: fit,
      errorWidget: errorWidget,
    );
  }

  factory PlatformImage.network(
    String networkUrl, {
    Key? key,
    double? width,
    double? height,
    BoxFit? fit,
    Widget? errorWidget,
    Widget? loadingWidget,
  }) {
    return PlatformImage(
      key: key,
      networkUrl: networkUrl,
      width: width,
      height: height,
      fit: fit,
      errorWidget: errorWidget,
      loadingWidget: loadingWidget,
    );
  }

  factory PlatformImage.memory(
    Uint8List imageData, {
    Key? key,
    double? width,
    double? height,
    BoxFit? fit,
    Widget? errorWidget,
  }) {
    return PlatformImage(
      key: key,
      imageData: imageData,
      width: width,
      height: height,
      fit: fit,
      errorWidget: errorWidget,
    );
  }

  factory PlatformImage.file(
    String filePath, {
    Key? key,
    double? width,
    double? height,
    BoxFit? fit,
    Widget? errorWidget,
  }) {
    return PlatformImage(
      key: key,
      filePath: filePath,
      width: width,
      height: height,
      fit: fit,
      errorWidget: errorWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      // Handle asset images
      if (assetPath != null) {
        return Image.asset(
          assetPath!,
          width: width,
          height: height,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget();
          },
        );
      }

      // Handle network images
      if (networkUrl != null) {
        return Image.network(
          networkUrl!,
          width: width,
          height: height,
          fit: fit ?? BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return loadingWidget ?? _buildLoadingWidget();
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget();
          },
        );
      }

      // Handle memory images
      if (imageData != null) {
        return Image.memory(
          imageData!,
          width: width,
          height: height,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget();
          },
        );
      }

      // Handle file images (only on mobile)
      if (filePath != null && !kIsWeb) {
        return Image.network(
          filePath!,
          width: width,
          height: height,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget();
          },
        );
      }

      // Fallback for web file paths - treat as network URLs
      if (filePath != null && kIsWeb) {
        return Image.network(
          filePath!,
          width: width,
          height: height,
          fit: fit ?? BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorWidget();
          },
        );
      }

      // No valid image source provided
      return _buildErrorWidget();
    } catch (e) {
      return _buildErrorWidget();
    }
  }

  Widget _buildErrorWidget() {
    return errorWidget ??
        Container(
          width: width ?? 100,
          height: height ?? 100,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.image_not_supported,
            color: Colors.grey,
            size: 40,
          ),
        );
  }

  Widget _buildLoadingWidget() {
    return loadingWidget ??
        Container(
          width: width ?? 100,
          height: height ?? 100,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
  }
}