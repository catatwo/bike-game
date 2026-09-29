import struct
import unittest

import ftms


class ParseBikeData(unittest.TestCase):
    def test_speed_cadence_power(self):
        d = ftms.parse_bike_data(bytes.fromhex("4400f609aa00c800"))
        self.assertEqual(d.speed_kmh, 25.5)
        self.assertEqual(d.cadence_rpm, 85)
        self.assertEqual(d.power_w, 200)
        self.assertIsNone(d.distance_m)

    def test_more_data_bit_means_no_speed(self):
        d = ftms.parse_bike_data(bytes.fromhex("4100c800"))
        self.assertIsNone(d.speed_kmh)
        self.assertEqual(d.power_w, 200)

    def test_distance_is_24_bit(self):
        d = ftms.parse_bike_data(bytes.fromhex("10000000452301"))
        self.assertEqual(d.distance_m, 0x012345)

    def test_every_field_lands_at_its_offset(self):
        packet = struct.pack(
            "<HHHHHHBhhhHHBBBH",
            0x0FFE,          # bits 1-11; bit 0 clear, so speed is there too
            3000, 2900,      # speed, average speed
            180, 170,        # cadence, average cadence (half rpm)
            0x5678, 0x01,    # distance, 24 bits
            -3,              # resistance
            -12, 150,        # power, average power
            100, 400, 7,     # energy: total, per hour, per minute
            141,             # heart rate
            52,              # metabolic equivalent
            3600,            # elapsed
        )
        d = ftms.parse_bike_data(packet)
        self.assertEqual(d.speed_kmh, 30)
        self.assertEqual(d.cadence_rpm, 90)
        self.assertEqual(d.distance_m, 0x015678)
        self.assertEqual(d.resistance, -3)
        self.assertEqual(d.power_w, -12)
        self.assertEqual(d.heart_rate, 141)
        self.assertEqual(d.elapsed_s, 3600)

    def test_short_packet_raises(self):
        with self.assertRaises(struct.error):
            ftms.parse_bike_data(bytes.fromhex("4400f609"))


class Commands(unittest.TestCase):
    def test_simulation_uphill(self):
        self.assertEqual(ftms.set_simulation(5.5).hex(), "11000026022833")

    def test_simulation_downhill(self):
        self.assertEqual(ftms.set_simulation(-3.25)[3:5], bytes.fromhex("bbfe"))

    def test_simulation_grade_is_clamped(self):
        self.assertEqual(ftms.set_simulation(400)[3:5],
                         struct.pack("<h", 32767))

    def test_target_power(self):
        self.assertEqual(ftms.set_target_power(250).hex(), "05fa00")

    def test_responses(self):
        self.assertEqual(ftms.parse_response(bytes.fromhex("801101")),
                         (0x11, "success"))
        self.assertEqual(ftms.parse_response(bytes.fromhex("800005")),
                         (0x00, "control not permitted"))
        self.assertIsNone(ftms.parse_response(bytes.fromhex("0102")))

    def test_features(self):
        f = ftms.parse_features(struct.pack("<II", 0x4000, 1 << 13 | 1 << 3))
        self.assertTrue(f.simulation)
        self.assertTrue(f.target_power)
        f = ftms.parse_features(struct.pack("<II", 0x4000, 1 << 2))
        self.assertFalse(f.simulation)
        self.assertFalse(f.target_power)


if __name__ == "__main__":
    unittest.main()


class Status(unittest.TestCase):
    def test_status_codes(self):
        self.assertEqual(ftms.parse_status(bytes([0xFF])), (0xFF, "control lost"))
        self.assertEqual(ftms.parse_status(bytes([0x04, 0x00])), (0x04, "started on the bike"))
        self.assertEqual(ftms.parse_status(bytes([0x42]))[1], "status 0x42")
        self.assertIsNone(ftms.parse_status(b""))
        self.assertEqual(ftms.parse_training_status(bytes([0x00, 0x01])), "idle")
        self.assertEqual(ftms.parse_training_status(bytes([0x00, 0x0D])), "manual mode (quick start)")
        self.assertIsNone(ftms.parse_training_status(b"\x00"))
