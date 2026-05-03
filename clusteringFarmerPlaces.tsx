
interface PlaceItem {
  placeId: number;
  farmerId: number;
  farmerName: string;
  avatar_url: string;
  image_place_url: string;
  rating: number;
  subscriptionScore: number;
  subscriptionDuration?: number;
  distance: number;
  address: string;
  coordinates: { lat: number; lng: number };
  is_subscribed: boolean;
  userid: number;
  has_eco_certificate: boolean;
  productCount: number;
  productCategories?: string[];
  products?: { id: string; name: string; objectName: string; isCategoryFallback?: boolean }[];
}

interface Cluster {
  id: number;
  points: PlaceItem[];
  size: number;
  avgDistance: number;
  avgRating: number;
  subscriptionRate: number;
  rank: number;
  rankScore: number;
  rankColor: string;
}

interface RankedPlace extends PlaceItem {
  clusterId: number;
  clusterRank: number;
  clusterRankColor: string;
  productCount: number;
  productCategories?: string[];
  individualScore: number;
}

interface RankedFarmerPlace {
  id: number;
  address: string;
  productCount: number;
  image_url: string;
  productCategories?: string[];
  distance: number;
  products?: { id: string; name: string; objectName: string; isCategoryFallback?: boolean }[];
  individualScore: number;
  clusterId: number;
  clusterRank: number;
}

interface RankedFarmer {
  id: number;
  name: string;
  rating: number;
  distance: number | null;
  is_subscribed: boolean;
  clusterId: number;
  userid: number;
  clusterRank: number;
  clusterRankColor: string;
  individualScore: number;
  bestPlaceId: number | null;
  bestPlaceAddress: string | null;
  placesCount: number;
  totalProducts: number;
  places: RankedFarmerPlace[];
  has_eco_certificate: boolean;  
}

function mercatorToLatLng(x: number, y: number): { lat: number; lng: number } {
  const lng = (x / 20037508.34) * 180;
  const lat = (Math.atan(Math.exp((y / 20037508.34) * Math.PI)) * 360 / Math.PI) - 90;
  return { lat, lng };
}

function haversineDistance(point1: Coordinate, point2: Coordinate): number {
  const R = 6371;
  const dLat = (point2.lat - point1.lat) * Math.PI / 180;
  const dLon = (point2.lng - point1.lng) * Math.PI / 180;
  const lat1 = point1.lat * Math.PI / 180;
  const lat2 = point2.lat * Math.PI / 180;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.sin(dLon / 2) * Math.sin(dLon / 2) * Math.cos(lat1) * Math.cos(lat2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function computeMedian(values: number[]): number {
  if (values.length === 0) return 1;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);

  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  return sorted[mid];
}

function computeCharacteristicDistance(distances: number[]): number {
  if (distances.length === 0) return 1;

  const logSum = distances.reduce((s, d) => s + Math.log(d + 1), 0);
  const geoMean = Math.exp(logSum / distances.length);
  const median = computeMedian(distances);
  const dChar = (geoMean + median) / 2;

  return dChar > 0 ? dChar : 1;
}

function normalizeDistance(distance: number, charDistance: number, alpha = 1.5): number {
  const safe = Math.max(charDistance, 1);
  return 1 / Math.pow(1 + distance / safe, alpha);
}

function normalizeRating(
  rating: number,
  distance: number,
  charDistance: number,
  lambda: number = 0.3
): number {
  const safeDChar = charDistance > 0 ? charDistance : 1;
  const r = Math.max(0, Math.min(5, rating)) / 5;
  const sig = 1 - Math.exp(-(lambda * distance) / safeDChar);
  return r * sig + 1 * (1 - sig);
}

function normalizeSubscription(
  subscriptionScore: number,
  distance: number,
  charDistance: number
): number {
  const safeDChar = charDistance > 0 ? charDistance : 1;
  return subscriptionScore * Math.exp(-distance / safeDChar);
}
function calculateEntropy(values: number[]): number {
  if (values.length === 0) return 0;

  const bins = Math.max(1, Math.ceil(Math.log2(values.length) + 1));
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min;

  if (range === 0) return 0;

  const histogram = new Array(bins).fill(0);

  for (const value of values) {
    const normalized = (value - min) / range;
    const index = Math.min(bins - 1, Math.floor(normalized * bins));
    histogram[index] += 1;
  }

  const total = values.length;
  const probs = histogram.map((h) => h / total).filter((p) => p > 0);

  const entropy = -probs.reduce((sum, p) => sum + p * Math.log2(p), 0);

  const maxEntropy = bins > 1 ? Math.log2(bins) : 1;

  return maxEntropy > 0 ? entropy / maxEntropy : 0;
}
function calculateEntropyWeights(places: PlaceItem[]) {
  const distances = places.map((p) => p.distance);
  const ratings = places.map((p) => p.rating);
  const subscriptions = places.map((p) => p.subscriptionScore);

  const Hd = calculateEntropy(distances);
  const Hr = calculateEntropy(ratings);
  const Hs = calculateEntropy(subscriptions);

  const sum = Hd + Hr + Hs;

  if (sum === 0) {
    return { distance: 0.34, rating: 0.33, subscription: 0.33 };
  }

  const weights = {
    distance: Hd / sum,
    rating: Hr / sum,
    subscription: Hs / sum
  };

  console.log('[entropy] values:', {
    Hd: Number(Hd.toFixed(4)),
    Hr: Number(Hr.toFixed(4)),
    Hs: Number(Hs.toFixed(4)),
    weights: {
      distance: Number(weights.distance.toFixed(4)),
      rating: Number(weights.rating.toFixed(4)),
      subscription: Number(weights.subscription.toFixed(4))
    }
  });

  return weights;
}
function clusterByDistance1D(
  places: PlaceItem[],
  gapMultiplier: number = 2.0
): Cluster[] {
  if (places.length === 0) return [];

  const sorted = [...places].sort((a, b) => a.distance - b.distance);

  if (sorted.length === 1) {
    return [{
      id: 0,
      points: sorted,
      size: 1,
      avgDistance: sorted[0].distance,
      avgRating: sorted[0].rating,
      subscriptionRate: sorted[0].subscriptionScore,
      rank: 0,
      rankScore: 0,
      rankColor: '#cccccc'
    }];
  }

  const gaps: number[] = [];
  for (let i = 1; i < sorted.length; i++) {
    gaps.push(sorted[i].distance - sorted[i - 1].distance);
  }

  const medianGap = computeMedian(gaps);

  const threshold = medianGap * gapMultiplier;

  console.log('[clusterByDistanceForPlaces] stats:', {
    totalPlaces: sorted.length,
    medianGap: medianGap.toFixed(2),
    gapMultiplier,
    threshold: threshold.toFixed(2),
    distanceRange: {
      min: sorted[0].distance.toFixed(1),
      max: sorted[sorted.length - 1].distance.toFixed(1)
    }
  });

  const rawClusters: PlaceItem[][] = [];
  let current: PlaceItem[] = [sorted[0]];

  for (let i = 1; i < sorted.length; i++) {
    const gap = sorted[i].distance - sorted[i - 1].distance;
    if (gap <= threshold) {
      current.push(sorted[i]);
    } else {
      rawClusters.push(current);
      current = [sorted[i]];
    }
  }

  if (current.length) {
    rawClusters.push(current);
  }

  return rawClusters.map((points, idx) => {
    const avgDistance = points.reduce((s, p) => s + p.distance, 0) / points.length;
    const avgRating = points.reduce((s, p) => s + p.rating, 0) / points.length;
    const subscriptionRate = points.reduce((s, p) => s + p.subscriptionScore, 0) / points.length;

    return {
      id: idx,
      points,
      size: points.length,
      avgDistance,
      avgRating,
      subscriptionRate,
      rank: 0,
      rankScore: 0,
      rankColor: '#cccccc'
    };
  });
}

function adaptiveClusterForPlaces(
  places: PlaceItem[],
  options: {
    minClusterSize?: number;
    maxClusters?: number;
    useElbowMethod?: boolean;      
    usePercentile?: boolean;       
  } = {}
): Cluster[] {
  const {
    minClusterSize = 2,
    maxClusters = 20,
    useElbowMethod = true,
  } = options;

  if (places.length === 0) return [];

  const sorted = [...places].sort((a, b) => a.distance - b.distance);

  if (sorted.length === 1) {
    return [{
      id: 0,
      points: sorted,
      size: 1,
      avgDistance: sorted[0].distance,
      avgRating: sorted[0].rating,
      subscriptionRate: sorted[0].subscriptionScore,
      rank: 0,
      rankScore: 0,
      rankColor: '#cccccc'
    }];
  }

  const gaps: number[] = [];
  for (let i = 1; i < sorted.length; i++) {
    gaps.push(sorted[i].distance - sorted[i - 1].distance);
  }

  const medianGap = computeMedian(gaps);
  const meanGap = gaps.reduce((a, b) => a + b, 0) / gaps.length;
  const stdGap = Math.sqrt(gaps.reduce((s, g) => s + Math.pow(g - meanGap, 2), 0) / gaps.length);
  const cv = stdGap / meanGap;

  const totalRange = sorted[sorted.length - 1].distance - sorted[0].distance;

  let gapMultiplier: number;
  if (cv < 0.3) {
    gapMultiplier = 1.2;  
  } else if (cv < 0.6) {
    gapMultiplier = 1.5;  
  } else if (cv < 1.0) {
    gapMultiplier = 2.0;  
  } else {
    gapMultiplier = 2.5;  
  }

  const percentile5 = sorted[Math.floor(sorted.length * 0.05)].distance;
  const minGapThresholdKm = Math.max(0.5, percentile5 * 0.05);

  const rangeThreshold = totalRange * 0.05;

  let elbowThreshold = Infinity;
  if (useElbowMethod && gaps.length > 2) {
    const sortedGaps = [...gaps].sort((a, b) => a - b);
    let maxJump = 0;
    let jumpIndex = 0;
    for (let i = 1; i < sortedGaps.length; i++) {
      const jump = sortedGaps[i] - sortedGaps[i - 1];
      if (jump > maxJump) {
        maxJump = jump;
        jumpIndex = i;
      }
    }
    elbowThreshold = sortedGaps[jumpIndex - 1];
  }

  let threshold = Math.max(minGapThresholdKm, gapMultiplier * medianGap);

  if (totalRange > 100) {
    threshold = Math.min(threshold, rangeThreshold * 1.5);
  }

  if (useElbowMethod && elbowThreshold !== Infinity && elbowThreshold > minGapThresholdKm && elbowThreshold < threshold * 2) {
    threshold = elbowThreshold;
  }

  let adjustedThreshold = threshold;

  let tempClusters = estimateClusterCount(sorted, adjustedThreshold);
  while (tempClusters > maxClusters && adjustedThreshold < totalRange * 0.3) {
    adjustedThreshold *= 1.2;
    tempClusters = estimateClusterCount(sorted, adjustedThreshold);
  }

  while (tempClusters < 2 && adjustedThreshold > minGapThresholdKm) {
    adjustedThreshold *= 0.8;
    tempClusters = estimateClusterCount(sorted, adjustedThreshold);
  }

  const finalThreshold = adjustedThreshold;

  console.log('[adaptiveClusterForPlaces] stats:', {
    medianGap: medianGap.toFixed(2),
    meanGap: meanGap.toFixed(2),
    cv: cv.toFixed(3),
    totalRange: totalRange.toFixed(2),
    gapMultiplier,
    minGapThresholdKm: minGapThresholdKm.toFixed(2),
    rangeThreshold: rangeThreshold.toFixed(2),
    elbowThreshold: elbowThreshold !== Infinity ? elbowThreshold.toFixed(2) : 'none',
    finalThreshold: finalThreshold.toFixed(2),
    estimatedClusters: tempClusters
  });

  const grouped: PlaceItem[][] = [];
  let currentCluster: PlaceItem[] = [sorted[0]];

  for (let i = 1; i < sorted.length; i++) {
    const gap = sorted[i].distance - sorted[i - 1].distance;
    if (gap <= finalThreshold) {
      currentCluster.push(sorted[i]);
    } else {
      if (currentCluster.length >= minClusterSize) {
        grouped.push(currentCluster);
      } else {

        if (grouped.length > 0) {
          grouped[grouped.length - 1].push(...currentCluster);
        } else if (i + 1 < sorted.length) {
          currentCluster.push(sorted[i]);
          continue;
        } else {
          grouped.push(currentCluster);
        }
      }
      currentCluster = [sorted[i]];
    }
  }

  if (currentCluster.length >= minClusterSize) {
    grouped.push(currentCluster);
  } else if (currentCluster.length > 0 && grouped.length > 0) {
    grouped[grouped.length - 1].push(...currentCluster);
  } else if (currentCluster.length > 0) {
    grouped.push(currentCluster);
  }

  return grouped.map((points, index) => {
    const avgDistance = points.reduce((sum, p) => sum + p.distance, 0) / points.length;
    const avgRating = points.reduce((sum, p) => sum + p.rating, 0) / points.length;
    const subscriptionRate = points.reduce((sum, p) => sum + p.subscriptionScore, 0) / points.length;

    return {
      id: index,
      points,
      size: points.length,
      avgDistance,
      avgRating,
      subscriptionRate,
      rank: 0,
      rankScore: 0,
      rankColor: '#cccccc'
    };
  });
}
function estimateClusterCount(sorted: any[], threshold: number): number {
  let count = 1;
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].distance - sorted[i - 1].distance > threshold) {
      count++;
    }
  }
  return count;
}
function calculatePlaceRank(
  place: PlaceItem,
  weights: { distance: number; rating: number; subscription: number },
  charDistance: number
): number {
  const Nd = normalizeDistance(place.distance, charDistance);
  const Nr = normalizeRating(place.rating, place.distance, charDistance);
  const Ns = normalizeSubscription(place.subscriptionScore, place.distance, charDistance);

  return 100 * (
    weights.distance * Nd +
    weights.rating * Nr +
    weights.subscription * Ns
  );
}

function calculateClusterRank(
  cluster: Cluster,
  weights: { distance: number; rating: number; subscription: number },
  charDistance: number
): number {
  const Nd = normalizeDistance(cluster.avgDistance, charDistance);
  const Nr = normalizeRating(cluster.avgRating, cluster.avgDistance, charDistance);
  const Ns = normalizeSubscription(cluster.subscriptionRate, cluster.avgDistance, charDistance);

  return 100 * (
    weights.distance * Nd +
    weights.rating * Nr +
    weights.subscription * Ns
  );
}
app.post('/api/buyer/clustered-farmers', authenticateToken, requireRole(3), async (req: Request, res: Response) => {
  try {
    //test
    const startedAt = Date.now();

    const userId = (req as any).user.userId;
    const { lat, lng, filters } = req.body;

    //test
    const t0 = Date.now();

    const calculateDistance = filters?.calculateDistance !== false;
    const maxDistance = Number(filters?.maxDistance ?? 500);
    const minRating = Number(filters?.minRating ?? 0);

    console.log('[API] request params:', {
      userId,
      lat,
      lng,
      calculateDistance,
      maxDistance,
      minRating,
      filters
    });

    const customerRes = await pool.query(
      'SELECT id FROM customers WHERE "idUser" = $1',
      [userId]
    );

    //test
    const t1 = Date.now();

    console.log('[API] customer query result:', customerRes.rows);

    if (customerRes.rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'profile doesnt exist'
      });
    }

    const customerId = customerRes.rows[0].id;

    const placesQuery = `
SELECT 
    s.id AS farmer_id,
    s.name AS farmer_name,
    sc.rating,
    s."userId",
    s."avatarUrl" AS avatar_url,
    p."imageUrl" AS place_image_url,
    sc.description,
    p.id AS place_id,
    p.address,
    p."kadastrNumber",
    p.area,
    ST_AsGeoJSON(ST_Transform(p.boundaries, 4326)) AS boundaries_geojson,
    ST_X(ST_Centroid(p.boundaries)) AS place_lng,
    ST_Y(ST_Centroid(p.boundaries)) AS place_lat,
    CASE WHEN fs.id IS NOT NULL THEN true ELSE false END AS is_subscribed,
    EXTRACT(DAY FROM (CURRENT_DATE - fs."createdAt")) AS subscription_days,
    COUNT(DISTINCT pr.id) AS product_count,
    ARRAY_AGG(DISTINCT pc.name) AS product_categories,
    ARRAY_AGG(DISTINCT no.name) FILTER (WHERE no.name IS NOT NULL) AS product_names,
    EXISTS (
        SELECT 1 
        FROM "farmerCertificates" fc
        WHERE fc."supplierId" = s.id 
          AND fc."certificateTypeId" = 1
          AND fc.status = 'active'
          AND (fc."expiryDate" IS NULL OR fc."expiryDate" > CURRENT_DATE)
    ) AS has_eco_certificate
FROM suppliers s
INNER JOIN "supplierCopies" sc ON s.id = sc."idSupplier" AND sc."isActual" = true
INNER JOIN "supplierPlaces" sp ON s.id = sp."idSupplier"
INNER JOIN places p ON sp."idPlace" = p.id
LEFT JOIN "farmerSubscriptions" fs ON fs."idCustomer" = $1 AND fs."idSupplier" = s.id
LEFT JOIN "supplierPlacesProducts" spp ON sp.id = spp."idSupplierPlace"
LEFT JOIN products pr ON spp."idProduct" = pr.id
LEFT JOIN "namesObjects" no ON pr."idObject" = no.id
LEFT JOIN "productCategories" pcats ON pr.id = pcats."idProduct"
LEFT JOIN "productCategory" pc ON pcats."idCategory" = pc.id
GROUP BY s.id, s.name, sc.rating, sc.description, p.id, p.address, p."kadastrNumber", p.area,
         p.boundaries, fs.id, fs."createdAt"
ORDER BY s.id, p.id
`;
    const placesResult = await pool.query(placesQuery, [customerId]);

    //test
    const t2 = Date.now();

    let filteredPlacesRows = placesResult.rows;

    if (filters?.ecoOnly === true) {
      filteredPlacesRows = filteredPlacesRows.filter(row => row.has_eco_certificate === true);
      console.log('[API] after ecoOnly filter:', filteredPlacesRows.length);
    }

    if (filteredPlacesRows.length === 0) {
      return res.json({
        success: true,
        clusters: { clusters: [] },
        allFarmers: [],
        allPlaces: []
      });
    }
    console.log('[API] places rows count:', placesResult.rows.length);
    console.log('[API] first 10 rows preview:', placesResult.rows.slice(0, 10));

    if (placesResult.rows.length === 0) {
      return res.json({
        success: true,
        clusters: { clusters: [] },
        allFarmers: [],
        allPlaces: []
      });
    }

    const places: PlaceItem[] = [];

    for (const row of filteredPlacesRows) {
      if (!calculateDistance) continue;
      if (!lat || !lng || !row.place_lat || !row.place_lng) continue;

      const coords = mercatorToLatLng(
        parseFloat(row.place_lng),
        parseFloat(row.place_lat)
      );

      const distance = haversineDistance(
        { lat: Number(lat), lng: Number(lng) },
        { lat: coords.lat, lng: coords.lng }
      );

      places.push({
        placeId: Number(row.place_id),
        farmerId: Number(row.farmer_id),
        farmerName: row.farmer_name,
        avatar_url: row.avatar_url,
        userid: Number(row.userId ?? row.userid),
        image_place_url: row.place_image_url,
        rating: row.rating ? parseFloat(row.rating) : 0,
        subscriptionScore: row.is_subscribed ? 1 : 0,
        subscriptionDuration: row.is_subscribed ? (row.subscription_days ?? 30) : undefined,
        distance,
        address: row.address || '',
        coordinates: coords,
        is_subscribed: !!row.is_subscribed,
        productCount: Number(row.product_count),
        has_eco_certificate: row.has_eco_certificate === true,  // Добавляем
        productCategories: row.product_categories ? row.product_categories.filter(Boolean) : [],
        products: Array.isArray(row.product_names)
          ? row.product_names
            .filter(Boolean)
            .map((name: string, idx: number) => ({
              id: `product-${row.place_id}-${idx}`,
              name,
              objectName: name
            }))
          : []
      });
    }

    //test
    const t3 = Date.now();

    console.log('[API] places after distance calculation:', places.length);
    console.log(
      '[API] places preview:',
      places.slice(0, 20).map((p) => ({
        placeId: p.placeId,
        farmerId: p.farmerId,
        farmerName: p.farmerName,
        distance: p.distance,
        rating: p.rating,
        subscription: p.subscriptionScore,
        address: p.address
      }))
    );

    let filteredPlaces = places.filter((p) => p.rating >= minRating);

    console.log('[API] after minRating filter:', filteredPlaces.length);

    if (calculateDistance) {
      filteredPlaces = filteredPlaces.filter((p) => p.distance <= maxDistance);
    }

    console.log('[API] after maxDistance filter:', filteredPlaces.length);
    console.log(
      '[API] filteredPlaces sorted by distance:',
      [...filteredPlaces]
        .sort((a, b) => a.distance - b.distance)
        .map((p) => ({
          placeId: p.placeId,
          farmerName: p.farmerName,
          distance: Number(p.distance.toFixed(2)),
          rating: p.rating
        }))
    );

    if (filteredPlaces.length === 0) {
      return res.json({
        success: true,
        clusters: { clusters: [] },
        allFarmers: [],
        allPlaces: []
      });
    }

    const characteristicDistance = computeCharacteristicDistance(
      filteredPlaces.map((p) => p.distance)
    );

    console.log('[API] characteristicDistance:', characteristicDistance);

    const entropyWeights = calculateEntropyWeights(filteredPlaces);
    console.log('[API] entropyWeights:', entropyWeights);

    const rawClusters = useAdaptiveClustering
      ? adaptiveClusterForPlaces(filteredPlaces, { minClusterSize: 2, maxClusters: 20 })
      : clusterByDistance1D(filteredPlaces, 2.0);

    const rankedClusters = rawClusters
      .map((cluster) => ({
        ...cluster,
        rankScore: calculateClusterRank(cluster, entropyWeights, characteristicDistance)
      }))
      .sort((a, b) => b.rankScore - a.rankScore);

    rankedClusters.forEach((cluster, index) => {
      cluster.rank = index + 1;
      cluster.rankColor = getRankColor(index + 1);
      cluster.points.sort((a, b) => a.distance - b.distance);
    });

    console.log(
      '[API] rankedClusters:',
      rankedClusters.map((c) => ({
        id: c.id,
        rank: c.rank,
        rankScore: Number(c.rankScore.toFixed(2)),
        size: c.size,
        avgDistance: Number(c.avgDistance.toFixed(2)),
        minDistance: Number(c.points[0]?.distance?.toFixed(2) || 0),
        maxDistance: Number(c.points[c.points.length - 1]?.distance?.toFixed(2) || 0)
      }))
    );

    const rankedPlaces: RankedPlace[] = filteredPlaces
      .map((place) => {
        const cluster = rankedClusters.find((c) =>
          c.points.some((p) => p.placeId === place.placeId)
        );

        return {
          ...place,
          clusterId: cluster?.id ?? -1,
          clusterRank: cluster?.rank ?? 999,
          clusterRankColor: cluster?.rankColor ?? '#cccccc',
          individualScore: calculatePlaceRank(place, entropyWeights, characteristicDistance)
        };
      })
      .sort((a, b) => {
        if (a.clusterRank !== b.clusterRank) return a.clusterRank - b.clusterRank;
        return b.individualScore - a.individualScore;
      });
    console.log(
      '[API] rankedPlaces final order:',
      rankedPlaces.map((p) => ({
        placeId: p.placeId,
        farmerName: p.farmerName,
        clusterRank: p.clusterRank,
        distance: Number(p.distance.toFixed(2)),
        score: Number(p.individualScore.toFixed(2))
      }))
    );

    //test
    const t4 = Date.now();

    const farmerMap = new Map<number, RankedFarmer>();

    for (const place of rankedPlaces) {
      const existing = farmerMap.get(place.farmerId);

      if (!existing) {
        farmerMap.set(place.farmerId, {
          id: place.farmerId,
          name: place.farmerName,
          rating: place.rating,
          distance: place.distance,
          is_subscribed: place.is_subscribed,
          clusterId: place.clusterId,
          clusterRank: place.clusterRank,
          userid: place.userid,
          clusterRankColor: place.clusterRankColor,
          individualScore: place.individualScore,
          bestPlaceId: place.placeId,
          bestPlaceAddress: place.address,
          placesCount: 1,
          has_eco_certificate: place.has_eco_certificate,
          totalProducts: 0,
          places: [
            {
              id: place.placeId,
              address: place.address,
              image_url: place.image_place_url,
              distance: place.distance,
              products: place.products ?? [],
              productCount: place.productCount,
              productCategories: place.productCategories,
              individualScore: place.individualScore,
              clusterId: place.clusterId,
              clusterRank: place.clusterRank
            }
          ]
        });
      } else {
        existing.placesCount += 1;
        existing.places.push({
          id: place.placeId,
          address: place.address,
          image_url: place.image_place_url,
          distance: place.distance,
          products: place.products ?? [],
          productCount: place.productCount,
          productCategories: place.productCategories,
          individualScore: place.individualScore,
          clusterId: place.clusterId,
          clusterRank: place.clusterRank
        });

        if (place.individualScore > existing.individualScore) {
          existing.rating = place.rating;
          existing.distance = place.distance;
          existing.is_subscribed = place.is_subscribed;
          existing.clusterId = place.clusterId;
          existing.clusterRank = place.clusterRank;
          existing.clusterRankColor = place.clusterRankColor;
          existing.individualScore = place.individualScore;
          existing.bestPlaceId = place.placeId;
          existing.bestPlaceAddress = place.address;
        }
      }
    }

    const allFarmers = Array.from(farmerMap.values())
      .map((farmer) => ({
        ...farmer,
        places: [...farmer.places].sort((a, b) => b.individualScore - a.individualScore)
      }))
      .sort((a, b) => {
        if (a.clusterRank !== b.clusterRank) return a.clusterRank - b.clusterRank;
        return b.individualScore - a.individualScore;
      });

    console.log(
      '[API] allFarmers final order:',
      allFarmers.map((f) => ({
        id: f.id,
        name: f.name,
        clusterRank: f.clusterRank,
        bestDistance: f.distance,
        bestScore: Number(f.individualScore.toFixed(2)),
        placesCount: f.placesCount,
        places: f.places.map((p) => ({
          placeId: p.id,
          distance: Number(p.distance.toFixed(2)),
          score: Number(p.individualScore.toFixed(2))
        }))
      }))
    );

    const clusterData = {
      clusters: rankedClusters.map((cluster) => ({
        id: cluster.id,
        rank: cluster.rank,
        rankScore: cluster.rankScore,
        rankColor: cluster.rankColor,
        size: cluster.size,
        avgDistance: cluster.avgDistance,
        avgRating: cluster.avgRating,
        subscriptionRate: cluster.subscriptionRate,
        farmers: cluster.points
          .map((p) => {
            const rankedPlace = rankedPlaces.find((rp) => rp.placeId === p.placeId);

            return {
              id: p.farmerId,
              name: p.farmerName,
              rating: p.rating,
              distance: p.distance,
              individualScore: rankedPlace?.individualScore ?? 0,
              is_subscribed: p.is_subscribed,
              x: normalizeDistance(p.distance, characteristicDistance) * 100,
              y: (Math.max(0, Math.min(5, p.rating)) / 5) * 100,
              bestPlaceAddress: p.address,
              placeId: p.placeId
            };
          })
          .sort((a, b) => b.individualScore - a.individualScore)
      })),
      characteristicDistance,
      entropyWeights
    };

    //test
    const t5 = Date.now();
    console.log('[clustered-farmers][timing]', {
      customerMs: t1 - t0,
      sqlMs: t2 - t1,
      transformMs: t3 - t2,
      clusteringMs: t4 - t3,
      responseMs: t5 - t4,
      totalMs: t5 - startedAt,
      placesRows: placesResult.rows.length,
      filteredRows: filteredPlacesRows.length
    });

    console.log('[API] response ready');

    return res.json({
      success: true,
      clusters: clusterData,
      allFarmers,
      allPlaces: rankedPlaces
    });
  } catch (error) {
    console.error('Cluster API error:', error);
    return res.status(500).json({
      success: false,
      message: 'server exception'
    });
  }
});