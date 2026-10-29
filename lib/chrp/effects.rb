def get_effects(classes)
  if classes == nil
    return nil
  end
  phy_effs = []
  cog_effs = []
  vis_effs = []
  for cc in classes
    case cc.downcase
    when "stimulant"
      phy_effs += [
        "Increased libido",
        "Stamina enhancement",
        "Stimulation",
        "Appetite suppression",
        "Dehydration",
        "Dry mouth",
        "Restless legs",
        "Shakiness",
        "Teeth grinding",
        "Abnormal heartbeat",
        "Increased blood pressure",
        "Increased heart rate",
        "Vasoconstriction"
      ]
      cog_effs += [
        "Analysis enhancement",
        "Ego inflation",
        "Focus enhancement",
        "Increased music appreciation",
        "Motivation enhancement",
        "Thought acceleration",
        "Wakefulness",
        "Disinhibition",
        "Suggestibility suppression",
        "Cognitive euphoria",
        "Compulsive redosing",
        "Mania"
      ]
    when "sympathomimetic"
      phy_effs += [
        "Stamina enhancement",
        "Dehydration",
        "Dry mouth",
        "Restless legs",
        "Shakiness",
        "Abnormal heartbeat",
        "Increased blood pressure",
        "Increased heart rate",
        "Vasoconstriction"
      ]
      cog_effs += [
        "Thought acceleration",
        "Wakefulness"
      ]
    when "entactogen"
      phy_effs += [
        "Increased libido",
        "Restless legs",
        "Shakiness",
        "Teeth grinding",
      ]
      cog_effs += [
        "Empathy, effection, and sociability enhancement",
        "Increased music appreciation",
        "Disinhibition",
        "Cognitive euphoria"
      ]
    when "psychedelic"
    when "opioid"
      phy_effs += [
        "Respiratory depression",
        "Pain relief",
        "Itchiness",
        "Constipation",
        "Cough suppression",
        "Sedation",
        "Nausea",
        "Pupil constriction",
        "Stomach cramp",
        "Difficulty urinating"
      ]
      cog_effs += [
        "Cognitive euphoria",
        "Thought deceleration",
        "Anxiety suppression",
        "Compulsive redosing",
        "Increased music appreciation"
      ]
      vis_effs += [
        "Double vision"
      ]
    end
  end
  if phy_effs.length == 0 && cog_effs.length == 0 && vis_effs.length == 0
    return nil
  end
  return { "Physical Effects": phy_effs.uniq, "Cognitive Effects": cog_effs.uniq, "Visual Effects": vis_effs.uniq }
end
