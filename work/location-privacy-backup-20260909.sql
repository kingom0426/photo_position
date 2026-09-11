-- MySQL dump 10.13  Distrib 9.6.0, for macos14.8 (x86_64)
--
-- Host: rm-2ze3w53wedri86606lo.mysql.rds.aliyuncs.com    Database: photo_position_db
-- ------------------------------------------------------
-- Server version	8.0.36

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `post_locations`
--

DROP TABLE IF EXISTS `post_locations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `post_locations` (
  `post_id` char(36) NOT NULL COMMENT '所属作品标识',
  `place_name` varchar(500) NOT NULL DEFAULT '' COMMENT '用户在地图上选定的定位地址',
  `city` varchar(80) NOT NULL DEFAULT '' COMMENT '拍摄地点所在城市',
  `district` varchar(100) NOT NULL DEFAULT '' COMMENT '拍摄地点所在区县',
  `detailed_address` varchar(500) NOT NULL DEFAULT '' COMMENT '用户手动输入的详细地址',
  `privacy_level` enum('EXACT','APPROXIMATE','PRIVATE') NOT NULL DEFAULT 'PRIVATE' COMMENT '地点公开级别：EXACT精确，APPROXIMATE模糊，PRIVATE不公开',
  `latitude` decimal(10,7) NOT NULL COMMENT '用户发布时选定的纬度',
  `longitude` decimal(10,7) NOT NULL COMMENT '用户发布时选定的经度',
  `shooting_advice` varchar(300) NOT NULL DEFAULT '' COMMENT '该地点的拍摄建议',
  `safety_status` enum('NORMAL','CAUTION','RESTRICTED') NOT NULL DEFAULT 'NORMAL' COMMENT '地点安全状态：NORMAL正常，CAUTION谨慎，RESTRICTED受限',
  PRIMARY KEY (`post_id`),
  KEY `idx_location_coordinates` (`city`,`latitude`,`longitude`),
  CONSTRAINT `fk_location_post` FOREIGN KEY (`post_id`) REFERENCES `posts` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='作品拍摄地点信息表';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `post_locations`
--

LOCK TABLES `post_locations` WRITE;
/*!40000 ALTER TABLE `post_locations` DISABLE KEYS */;
INSERT INTO `post_locations` VALUES ('011a3b5b-fcee-4f14-ba90-be9a02c53029','北京市朝阳区望京西路','北京','','','EXACT',39.9891414,116.4569259,'','NORMAL');
/*!40000 ALTER TABLE `post_locations` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-09-09 14:14:36
