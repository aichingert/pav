package com.example.examplemod;

import net.minecraft.client.Minecraft;
import net.minecraft.world.entity.MoverType;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.phys.Vec3;
import net.minecraftforge.client.event.ClientChatEvent;
import net.minecraftforge.common.MinecraftForge;
import net.minecraftforge.eventbus.api.SubscribeEvent;
import net.minecraftforge.fml.common.Mod;

// The value here should match an entry in the META-INF/mods.toml file
@Mod(ExampleMod.MODID)
public class ExampleMod
{
    public static final String MODID = "examplemod";

    public ExampleMod() {
        MinecraftForge.EVENT_BUS.register(this);
    }

    @SubscribeEvent
    public void onChat(ClientChatEvent event) {
        if (event.getMessage().equalsIgnoreCase("a")) {
            Minecraft mc = Minecraft.getInstance();
            Player player = mc.player;
            assert player != null;
            player.setSprinting(true);

            new Thread(() -> {
                while (true) {
                    player.move(MoverType.SELF, new Vec3(1, 0, 0));

                    try {
                        Thread.sleep(100);
                    } catch (Exception ignored) {}
                }
            }).start();
        }
    }
}
